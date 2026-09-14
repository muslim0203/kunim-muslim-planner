/// Data access for `SleepLogs`: at most one live night per local wake-up day.
///
/// ADR-0002 rule 12: natural key `(user_id, coalesce(ref_id, ''), date)`;
/// `bed_time`/`wake_time` merge as one last-write-wins pair and
/// `duration_min` is derived from them, so this repository always computes
/// it rather than accepting it from callers.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';
import '../../../core/db/daily_log_fields.dart';
import '../../../core/db/local_write_hook.dart';
import '../../../core/sync/conflict.dart' show toRfc3339Millis, toWireDate;
import '../../habits/domain/local_day.dart';
import '../domain/sleep_limits.dart';

class SleepLogRepository extends SyncableRepository with LocalWriteHook {
  SleepLogRepository(
    super.db, {
    required this.onLocalWrite,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  @override
  final void Function() onLocalWrite;
  final DateTime Function() _now;

  static const String entityName = 'sleep_logs';

  Stream<SleepLog?> watchForDay(LocalDay day, {String? userId}) =>
      _liveForDay(day, userId).watchSingleOrNull();

  Stream<List<SleepLog>> watchRecent({int limit = 60, String? userId}) {
    final query = db.select(db.sleepLogs)
      ..where((l) => l.deletedAt.isNull() & _userIdMatches(l, userId))
      ..orderBy([(l) => OrderingTerm.desc(l.date)])
      ..limit(limit);
    return query.watch();
  }

  /// Creates or replaces the night that ended on [wakeDay]. Times are
  /// truncated to whole minutes; the night must last 1 minute .. 24 hours.
  Future<SleepLog> saveForDay(
    LocalDay wakeDay, {
    required DateTime bedTime,
    required DateTime wakeTime,
    int? quality,
    String? note,
    String? userId,
  }) async {
    final bed = toUtcMinute(bedTime);
    final wake = toUtcMinute(wakeTime);
    final duration = durationMinutes(bed, wake);
    if (duration < 1 || duration > SleepLimits.maxDurationMin) {
      throw ArgumentError('the night must last 1 minute to 24 hours');
    }
    if (quality != null &&
        (quality < SleepLimits.minQuality ||
            quality > SleepLimits.maxQuality)) {
      throw ArgumentError.value(quality, 'quality');
    }
    final cleanNote = normalizeNote(note);
    final now = _now().toUtc();
    final existing = await _liveForDay(wakeDay, userId).getSingleOrNull();

    if (existing == null) {
      final row = SleepLog(
        id: const Uuid().v4(),
        userId: userId,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        serverVersion: 0,
        dirty: true,
        refId: null,
        date: wakeDay.toUtcMidnight(),
        bedTime: bed,
        wakeTime: wake,
        durationMin: duration,
        quality: quality,
        note: cleanNote,
      );
      await writeAndNotify<void>(
        entity: entityName,
        rowId: row.id,
        op: SyncOp.upsert,
        payload: _payloadOf(row),
        write: () => db.into(db.sleepLogs).insert(row.toCompanion(false)),
      );
      return row;
    }

    final patch = SleepLogsCompanion(
      bedTime: Value(bed),
      wakeTime: Value(wake),
      durationMin: Value(duration),
      quality: Value(quality),
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
      write: () => (db.update(db.sleepLogs)
            ..where((l) => l.id.equals(existing.id)))
          .write(patch),
    );
    return merged;
  }

  Future<void> deleteForDay(LocalDay wakeDay, {String? userId}) async {
    final existing = await _liveForDay(wakeDay, userId).getSingleOrNull();
    if (existing == null) return;
    final now = _now().toUtc();
    final patch = SleepLogsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      dirty: const Value(true),
    );
    await writeAndNotify<void>(
      entity: entityName,
      rowId: existing.id,
      op: SyncOp.delete,
      payload: _payloadOf(existing.copyWithCompanion(patch)),
      write: () => (db.update(db.sleepLogs)
            ..where((l) => l.id.equals(existing.id)))
          .write(patch),
    );
  }

  /// Whole minutes between two instants, as the server derives it.
  static int durationMinutes(DateTime bed, DateTime wake) =>
      wake.difference(bed).inMinutes;

  SimpleSelectStatement<$SleepLogsTable, SleepLog> _liveForDay(
    LocalDay day,
    String? userId,
  ) {
    return db.select(db.sleepLogs)
      ..where(
        (l) =>
            l.date.equals(day.toUtcMidnight()) &
            l.deletedAt.isNull() &
            _userIdMatches(l, userId),
      )
      ..limit(1);
  }

  Map<String, dynamic> _payloadOf(SleepLog row) => {
        'id': row.id,
        'user_id': row.userId,
        'ref_id': row.refId,
        'date': toWireDate(row.date),
        'bed_time': toRfc3339Millis(row.bedTime),
        'wake_time': toRfc3339Millis(row.wakeTime),
        'duration_min': row.durationMin,
        'quality': row.quality,
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
Expression<bool> _userIdMatches($SleepLogsTable t, String? userId) =>
    userId == null ? const Constant(true) : t.userId.equals(userId);
