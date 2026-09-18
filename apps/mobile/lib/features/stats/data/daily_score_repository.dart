/// Data access for `DailyScores`: at most one live row per local day.
///
/// ADR-0002 rule 26: natural key `(user_id, date)`, and every number merges
/// max-wins on the server. The row is written from the score the device
/// computed (`domain/daily_score.dart`) — it is a report of local work, not a
/// second source of truth: nothing reads the points back to display them.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';
import '../../../core/db/local_write_hook.dart';
import '../../../core/sync/conflict.dart' show toRfc3339Millis, toWireDate;
import '../../habits/domain/local_day.dart';

class DailyScoreRepository extends SyncableRepository with LocalWriteHook {
  DailyScoreRepository(
    super.db, {
    required this.onLocalWrite,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  @override
  final void Function() onLocalWrite;
  final DateTime Function() _now;

  static const String entityName = 'daily_scores';

  /// The live row for [day], or `null`.
  Future<DailyScore?> findForDay(LocalDay day) =>
      _liveForDay(day).getSingleOrNull();

  /// Records [day]'s score, unless the stored row already says the same — a
  /// score is recomputed on every change, and rewriting an identical row
  /// would queue an outbox entry for nothing.
  Future<DailyScore?> saveForDay(
    LocalDay day, {
    required int points,
    required int done,
    required int planned,
  }) async {
    final existing = await _liveForDay(day).getSingleOrNull();
    if (existing != null &&
        existing.points == points &&
        existing.done == done &&
        existing.planned == planned) {
      return existing;
    }

    final now = _now().toUtc();
    if (existing == null) {
      final row = DailyScore(
        id: const Uuid().v4(),
        userId: null,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        serverVersion: 0,
        dirty: true,
        date: day.toUtcMidnight(),
        points: points,
        done: done,
        planned: planned,
      );
      await writeAndNotify<void>(
        entity: entityName,
        rowId: row.id,
        op: SyncOp.upsert,
        payload: _payloadOf(row),
        write: () => db.into(db.dailyScores).insert(row.toCompanion(false)),
      );
      return row;
    }

    final patch = DailyScoresCompanion(
      points: Value(points),
      done: Value(done),
      planned: Value(planned),
      updatedAt: Value(now),
      dirty: const Value(true),
    );
    final merged = existing.copyWithCompanion(patch);
    await writeAndNotify<void>(
      entity: entityName,
      rowId: existing.id,
      op: SyncOp.upsert,
      payload: _payloadOf(merged),
      write: () => (db.update(db.dailyScores)
            ..where((row) => row.id.equals(existing.id)))
          .write(patch),
    );
    return merged;
  }

  SimpleSelectStatement<$DailyScoresTable, DailyScore> _liveForDay(
    LocalDay day,
  ) {
    return db.select(db.dailyScores)
      ..where(
        (row) => row.date.equals(day.toUtcMidnight()) & row.deletedAt.isNull(),
      )
      ..limit(1);
  }

  /// Snake_case wire row (ADR-0002 §3); `date` is a DATE.
  Map<String, dynamic> _payloadOf(DailyScore row) => {
        'id': row.id,
        'user_id': row.userId,
        'date': toWireDate(row.date),
        'points': row.points,
        'done': row.done,
        'planned': row.planned,
        'created_at': toRfc3339Millis(row.createdAt),
        'updated_at': toRfc3339Millis(row.updatedAt),
        'deleted_at':
            row.deletedAt == null ? null : toRfc3339Millis(row.deletedAt!),
        'server_version': row.serverVersion,
      };
}
