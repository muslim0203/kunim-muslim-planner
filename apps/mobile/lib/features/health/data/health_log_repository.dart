/// Data access for `HealthLogs`: at most one live entry per local day.
///
/// ADR-0002 rule 13: natural key `(user_id, coalesce(ref_id, ''), date)`;
/// `water_ml`, `steps`, `workout_min` and `calories` merge max-wins on the
/// server (a lower value typed here can be overridden by a higher one from
/// another device, by design); `weight_kg` and `note` are last-write-wins.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';
import '../../../core/db/daily_log_fields.dart';
import '../../../core/db/local_write_hook.dart';
import '../../../core/sync/conflict.dart' show toRfc3339Millis, toWireDate;
import '../../habits/domain/local_day.dart';
import '../domain/health_limits.dart';

class HealthLogRepository extends SyncableRepository with LocalWriteHook {
  HealthLogRepository(
    super.db, {
    required this.onLocalWrite,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  @override
  final void Function() onLocalWrite;
  final DateTime Function() _now;

  static const String entityName = 'health_logs';

  Stream<HealthLog?> watchForDay(LocalDay day, {String? userId}) =>
      _liveForDay(day, userId).watchSingleOrNull();

  Stream<List<HealthLog>> watchRecent({int limit = 60, String? userId}) {
    final query = db.select(db.healthLogs)
      ..where((l) => l.deletedAt.isNull() & _userIdMatches(l, userId))
      ..orderBy([(l) => OrderingTerm.desc(l.date)])
      ..limit(limit);
    return query.watch();
  }

  /// Creates or replaces [day]'s entry. At least one metric or a note is
  /// required; every value must be within [HealthLimits].
  Future<HealthLog> saveForDay(
    LocalDay day, {
    int? waterMl,
    int? steps,
    int? workoutMin,
    int? calories,
    double? weightKg,
    String? note,
    String? userId,
  }) async {
    _checkRange(waterMl, 0, HealthLimits.maxWaterMl, 'waterMl');
    _checkRange(steps, 0, HealthLimits.maxSteps, 'steps');
    _checkRange(workoutMin, 0, HealthLimits.maxWorkoutMin, 'workoutMin');
    _checkRange(calories, 0, HealthLimits.maxCalories, 'calories');
    if (weightKg != null &&
        (weightKg < HealthLimits.minWeightKg ||
            weightKg > HealthLimits.maxWeightKg)) {
      throw ArgumentError.value(weightKg, 'weightKg');
    }
    final cleanNote = normalizeNote(note);
    if (waterMl == null &&
        steps == null &&
        workoutMin == null &&
        calories == null &&
        weightKg == null &&
        cleanNote == null) {
      throw ArgumentError('a health entry needs at least one value');
    }
    final now = _now().toUtc();
    final existing = await _liveForDay(day, userId).getSingleOrNull();

    if (existing == null) {
      final row = HealthLog(
        id: const Uuid().v4(),
        userId: userId,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        serverVersion: 0,
        dirty: true,
        refId: null,
        date: day.toUtcMidnight(),
        waterMl: waterMl,
        steps: steps,
        workoutMin: workoutMin,
        calories: calories,
        weightKg: weightKg,
        note: cleanNote,
      );
      await writeAndNotify<void>(
        entity: entityName,
        rowId: row.id,
        op: SyncOp.upsert,
        payload: _payloadOf(row),
        write: () => db.into(db.healthLogs).insert(row.toCompanion(false)),
      );
      return row;
    }

    final patch = HealthLogsCompanion(
      waterMl: Value(waterMl),
      steps: Value(steps),
      workoutMin: Value(workoutMin),
      calories: Value(calories),
      weightKg: Value(weightKg),
      note: Value(cleanNote),
      updatedAt: Value(now),
      dirty: const Value(true),
    );
    final merged = existing.copyWithCompanion(patch);
    await writeAndNotify<void>(
      entity: entityName,
      rowId: existing.id,
      op: SyncOp.upsert,
      payload: _payloadOf(merged),
      write: () => (db.update(db.healthLogs)
            ..where((l) => l.id.equals(existing.id)))
          .write(patch),
    );
    return merged;
  }

  Future<void> deleteForDay(LocalDay day, {String? userId}) async {
    final existing = await _liveForDay(day, userId).getSingleOrNull();
    if (existing == null) return;
    final now = _now().toUtc();
    final patch = HealthLogsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      dirty: const Value(true),
    );
    await writeAndNotify<void>(
      entity: entityName,
      rowId: existing.id,
      op: SyncOp.delete,
      payload: _payloadOf(existing.copyWithCompanion(patch)),
      write: () => (db.update(db.healthLogs)
            ..where((l) => l.id.equals(existing.id)))
          .write(patch),
    );
  }

  static void _checkRange(int? value, int min, int max, String name) {
    if (value != null && (value < min || value > max)) {
      throw ArgumentError.value(value, name);
    }
  }

  SimpleSelectStatement<$HealthLogsTable, HealthLog> _liveForDay(
    LocalDay day,
    String? userId,
  ) {
    return db.select(db.healthLogs)
      ..where(
        (l) =>
            l.date.equals(day.toUtcMidnight()) &
            l.deletedAt.isNull() &
            _userIdMatches(l, userId),
      )
      ..limit(1);
  }

  Map<String, dynamic> _payloadOf(HealthLog row) => {
        'id': row.id,
        'user_id': row.userId,
        'ref_id': row.refId,
        'date': toWireDate(row.date),
        'water_ml': row.waterMl,
        'steps': row.steps,
        'workout_min': row.workoutMin,
        'calories': row.calories,
        'weight_kg': row.weightKg,
        'note': row.note,
        'created_at': toRfc3339Millis(row.createdAt),
        'updated_at': toRfc3339Millis(row.updatedAt),
        'deleted_at':
            row.deletedAt == null ? null : toRfc3339Millis(row.deletedAt!),
        'server_version': row.serverVersion,
      };
}

/// A `null` [userId] matches every row: the device holds one account's
/// data at a time, whether its rows were created here (and stamped with
/// the signed-in account) or pulled from the server.
Expression<bool> _userIdMatches($HealthLogsTable t, String? userId) =>
    userId == null ? const Constant(true) : t.userId.equals(userId);
