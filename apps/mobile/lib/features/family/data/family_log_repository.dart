/// Data access for `FamilyLogs`: at most one live entry per local day.
///
/// Natural key `(user_id, coalesce(ref_id, ''), date)`; on the server
/// `minutes` merges max-wins, `activities` as a set union and `note`
/// last-write-wins.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';
import '../../../core/db/daily_log_fields.dart';
import '../../../core/db/local_write_hook.dart';
import '../../../core/sync/conflict.dart' show toRfc3339Millis, toWireDate;
import '../../habits/domain/local_day.dart';
import '../domain/family_options.dart';

class FamilyLogRepository extends SyncableRepository with LocalWriteHook {
  FamilyLogRepository(
    super.db, {
    required this.onLocalWrite,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  @override
  final void Function() onLocalWrite;
  final DateTime Function() _now;

  static const String entityName = 'family_logs';

  Stream<FamilyLog?> watchForDay(LocalDay day, {String? userId}) =>
      _liveForDay(day, userId).watchSingleOrNull();

  Stream<List<FamilyLog>> watchRecent({int limit = 60, String? userId}) {
    final query = db.select(db.familyLogs)
      ..where((l) => l.deletedAt.isNull() & _userIdMatches(l, userId))
      ..orderBy([(l) => OrderingTerm.desc(l.date)])
      ..limit(limit);
    return query.watch();
  }

  /// Creates or replaces [day]'s entry. Needs minutes, an activity or a
  /// note.
  Future<FamilyLog> saveForDay(
    LocalDay day, {
    int? minutes,
    Iterable<String> activities = const [],
    String? note,
    String? userId,
  }) async {
    if (minutes != null &&
        (minutes < 0 || minutes > FamilyOptions.maxMinutes)) {
      throw ArgumentError.value(minutes, 'minutes');
    }
    final codes = normalizeCodes(activities, FamilyOptions.activities);
    final cleanNote = normalizeNote(note);
    if (minutes == null && codes.isEmpty && cleanNote == null) {
      throw ArgumentError('a family entry needs at least one value');
    }
    final now = _now().toUtc();
    final existing = await _liveForDay(day, userId).getSingleOrNull();

    if (existing == null) {
      final row = FamilyLog(
        id: const Uuid().v4(),
        userId: userId,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        serverVersion: 0,
        dirty: true,
        refId: null,
        date: day.toUtcMidnight(),
        minutes: minutes,
        activities: encodeCodes(codes),
        note: cleanNote,
      );
      await writeAndNotify<void>(
        entity: entityName,
        rowId: row.id,
        op: SyncOp.upsert,
        payload: _payloadOf(row),
        write: () => db.into(db.familyLogs).insert(row.toCompanion(false)),
      );
      return row;
    }

    final patch = FamilyLogsCompanion(
      minutes: Value(minutes),
      activities: Value(encodeCodes(codes)),
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
      write: () => (db.update(db.familyLogs)
            ..where((l) => l.id.equals(existing.id)))
          .write(patch),
    );
    return merged;
  }

  Future<void> deleteForDay(LocalDay day, {String? userId}) async {
    final existing = await _liveForDay(day, userId).getSingleOrNull();
    if (existing == null) return;
    final now = _now().toUtc();
    final patch = FamilyLogsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      dirty: const Value(true),
    );
    await writeAndNotify<void>(
      entity: entityName,
      rowId: existing.id,
      op: SyncOp.delete,
      payload: _payloadOf(existing.copyWithCompanion(patch)),
      write: () => (db.update(db.familyLogs)
            ..where((l) => l.id.equals(existing.id)))
          .write(patch),
    );
  }

  static List<String> activitiesOf(FamilyLog row) =>
      decodeCodes(row.activities);

  SimpleSelectStatement<$FamilyLogsTable, FamilyLog> _liveForDay(
    LocalDay day,
    String? userId,
  ) {
    return db.select(db.familyLogs)
      ..where(
        (l) =>
            l.date.equals(day.toUtcMidnight()) &
            l.deletedAt.isNull() &
            _userIdMatches(l, userId),
      )
      ..limit(1);
  }

  Map<String, dynamic> _payloadOf(FamilyLog row) => {
        'id': row.id,
        'user_id': row.userId,
        'ref_id': row.refId,
        'date': toWireDate(row.date),
        'minutes': row.minutes,
        'activities': decodeCodes(row.activities),
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
Expression<bool> _userIdMatches($FamilyLogsTable t, String? userId) =>
    userId == null ? const Constant(true) : t.userId.equals(userId);
