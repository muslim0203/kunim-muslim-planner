/// Data access for `HabitLogs` — one habit's completion record for one
/// calendar day.
///
/// **ADR-0002 conflict-matrix rule 9 (read before touching this file):**
/// `habit_logs`' natural key is `(user_id, habit_id, date)`; `count` and
/// `value` are merged **max-wins** on the server, `note` is plain LWW. This
/// means a local decrement of `count` (e.g. "oops, tap undo") can be
/// clobbered by a higher value already on the server from another device
/// the next time this device syncs — that is deliberate server behaviour,
/// not a bug, and this file does not attempt to work around it
/// client-side (there is nothing to work around locally: the client
/// always writes the count it locally believes is correct; the merge
/// happens only in `apps/api/app/modules/sync/merge.py`).
///
/// **Rule 14:** two devices creating a log for the same `(habit_id, date)`
/// with different ids get merged server-side; the losing row is
/// tombstoned (`deleted_at` set) with a `merged_into` marker in its
/// payload. This table has no local `merged_into` column (nothing here
/// needs to know *why* a row is tombstoned) — every read in this file
/// filters `deletedAt.isNull()`, so a tombstoned loser simply never
/// appears, regardless of the reason.
///
/// **No foreign key:** `habitId` is a loose reference (see
/// `core/db/tables/habits_table.dart`) — a log can arrive (via sync)
/// before its habit does. Every query here tolerates that; see
/// [watchLogsForDate], which left-joins against `Habits` and reports a
/// missing habit as `null` rather than dropping the row or throwing.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';
import '../../../core/sync/conflict.dart' show toRfc3339Millis, toWireDate;
import '../domain/local_day.dart';
import 'habit_local_write_hook.dart';

/// A [HabitLog] paired with its [Habit], when known. [habit] is `null`
/// when the referenced habit has not synced to this device yet (or was
/// deleted) — see the class doc.
class HabitLogWithHabit {
  const HabitLogWithHabit({required this.log, required this.habit});

  final HabitLog log;
  final Habit? habit;
}

class HabitLogRepository extends SyncableRepository with HabitLocalWriteHook {
  HabitLogRepository(super.db, {required this.onLocalWrite});

  @override
  final void Function() onLocalWrite;

  static const String entityName = 'habit_logs';

  // --- Reads (reactive) ---------------------------------------------------

  /// Every live log across all habits, oldest first. Read-only; used by the
  /// statistics screen, which needs full history to compute streaks.
  Stream<List<HabitLog>> watchAllLogs({String? userId}) {
    final query = db.select(db.habitLogs)
      ..where((l) => l.deletedAt.isNull() & _userIdMatches(l, userId))
      ..orderBy([(l) => OrderingTerm.asc(l.date)]);
    return query.watch();
  }

  /// A habit's full log history, newest first. Never returns a tombstoned
  /// row.
  Stream<List<HabitLog>> watchLogsForHabit(String habitId, {String? userId}) {
    final query = db.select(db.habitLogs)
      ..where(
        (l) =>
            l.habitId.equals(habitId) &
            l.deletedAt.isNull() &
            _userIdMatches(l, userId),
      )
      ..orderBy([(l) => OrderingTerm.desc(l.date)]);
    return query.watch();
  }

  /// The live log row for one habit on one day, or `null` if none exists
  /// (not logged, or removed via [removeLog]).
  Stream<HabitLog?> watchLogForDay({
    required String habitId,
    required LocalDay day,
    String? userId,
  }) {
    final query = db.select(db.habitLogs)
      ..where(
        (l) =>
            l.habitId.equals(habitId) &
            l.date.equals(day.toUtcMidnight()) &
            l.deletedAt.isNull() &
            _userIdMatches(l, userId),
      );
    return query.watchSingleOrNull();
  }

  /// Every live log dated [day], across all habits, each paired with its
  /// [Habit] if this device has it (see class doc — a missing habit
  /// reports `null`, it never crashes or drops the log).
  Stream<List<HabitLogWithHabit>> watchLogsForDate(
    LocalDay day, {
    String? userId,
  }) {
    final query = db.select(db.habitLogs).join([
      leftOuterJoin(db.habits, db.habits.id.equalsExp(db.habitLogs.habitId)),
    ])
      ..where(
        db.habitLogs.date.equals(day.toUtcMidnight()) &
            db.habitLogs.deletedAt.isNull() &
            _userIdMatches(db.habitLogs, userId),
      );
    return query.watch().map(
          (rows) => rows
              .map(
                (row) => HabitLogWithHabit(
                  log: row.readTable(db.habitLogs),
                  habit: row.readTableOrNull(db.habits),
                ),
              )
              .toList(growable: false),
        );
  }

  Future<HabitLog?> _findLive({
    required String habitId,
    required LocalDay day,
    String? userId,
  }) {
    final query = db.select(db.habitLogs)
      ..where(
        (l) =>
            l.habitId.equals(habitId) &
            l.date.equals(day.toUtcMidnight()) &
            l.deletedAt.isNull() &
            _userIdMatches(l, userId),
      );
    return query.getSingleOrNull();
  }

  // --- Mutations -----------------------------------------------------------

  /// Records a completion for [day] — the common "mark done" action.
  /// Convenience for `adjustCount(delta: 1)`.
  Future<void> logCompletion({
    required String habitId,
    required LocalDay day,
    String? userId,
  }) {
    return adjustCount(habitId: habitId, day: day, userId: userId, delta: 1);
  }

  /// Adjusts (increments or decrements) [day]'s logged `count` for a
  /// habit, creating the day's row if it does not exist yet. The local
  /// result is clamped at 0 — never negative — but see rule 9 in the
  /// class doc: after the next sync, the server may still show a HIGHER
  /// count from another device; this method does not and cannot prevent
  /// that, by design.
  Future<void> adjustCount({
    required String habitId,
    required LocalDay day,
    String? userId,
    int delta = 1,
  }) async {
    final existing =
        await _findLive(habitId: habitId, day: day, userId: userId);
    final now = DateTime.now().toUtc();

    if (existing == null) {
      final count = delta < 0 ? 0 : delta;
      await _insert(
        userId: userId,
        habitId: habitId,
        date: day.toUtcMidnight(),
        now: now,
        count: count,
      );
      return;
    }

    final newCount = existing.count + delta;
    await _update(
      existing,
      HabitLogsCompanion(
        count: Value(newCount < 0 ? 0 : newCount),
        updatedAt: Value(now),
      ),
    );
  }

  /// Same as [adjustCount] but for the numeric `value` column (e.g. a
  /// duration- or amount-tracked habit). Not clamped beyond staying
  /// non-negative, for the same rule-9 reason as [adjustCount].
  Future<void> adjustValue({
    required String habitId,
    required LocalDay day,
    String? userId,
    required double delta,
  }) async {
    final existing =
        await _findLive(habitId: habitId, day: day, userId: userId);
    final now = DateTime.now().toUtc();

    if (existing == null) {
      await _insert(
        userId: userId,
        habitId: habitId,
        date: day.toUtcMidnight(),
        now: now,
        count: 0,
        value: delta < 0 ? 0 : delta,
      );
      return;
    }

    final newValue = (existing.value ?? 0) + delta;
    await _update(
      existing,
      HabitLogsCompanion(
        value: Value(newValue < 0 ? 0 : newValue),
        updatedAt: Value(now),
      ),
    );
  }

  /// Sets (replaces) [day]'s note, creating the day's row (with `count:
  /// 0`) if it does not exist yet — a note alone does not imply a
  /// completion. `note` is plain LWW server-side (rule 9), unlike
  /// `count`/`value`.
  Future<void> setNote({
    required String habitId,
    required LocalDay day,
    String? userId,
    String? note,
  }) async {
    final existing =
        await _findLive(habitId: habitId, day: day, userId: userId);
    final now = DateTime.now().toUtc();

    if (existing == null) {
      await _insert(
        userId: userId,
        habitId: habitId,
        date: day.toUtcMidnight(),
        now: now,
        count: 0,
        note: note,
      );
      return;
    }

    await _update(
      existing,
      HabitLogsCompanion(note: Value(note), updatedAt: Value(now)),
    );
  }

  /// Removes (soft-deletes) [day]'s log entirely, if one exists. A no-op
  /// otherwise.
  Future<void> removeLog({
    required String habitId,
    required LocalDay day,
    String? userId,
  }) async {
    final existing =
        await _findLive(habitId: habitId, day: day, userId: userId);
    if (existing == null) return;

    final now = DateTime.now().toUtc();
    final patch = HabitLogsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      dirty: const Value(true),
    );
    final merged = existing.copyWithCompanion(patch);

    await writeAndNotify<void>(
      entity: entityName,
      rowId: existing.id,
      op: SyncOp.delete,
      payload: _payloadOf(merged),
      write: () => (db.update(
        db.habitLogs,
      )..where((l) => l.id.equals(existing.id)))
          .write(patch),
    );
  }

  // --- Shared write helpers ------------------------------------------------

  Future<void> _insert({
    required String? userId,
    required String habitId,
    required DateTime date,
    required DateTime now,
    required int count,
    double? value,
    String? note,
  }) {
    final id = const Uuid().v4();
    final row = HabitLog(
      id: id,
      userId: userId,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      serverVersion: 0,
      dirty: true,
      habitId: habitId,
      date: date,
      count: count,
      value: value,
      note: note,
    );
    return writeAndNotify<void>(
      entity: entityName,
      rowId: id,
      op: SyncOp.upsert,
      payload: _payloadOf(row),
      write: () => db.into(db.habitLogs).insert(row.toCompanion(false)),
    );
  }

  Future<void> _update(HabitLog existing, HabitLogsCompanion patch) {
    // Re-arm `dirty` for every local edit, whatever the caller patched: a
    // forced full resync deletes `dirty = 0` rows, so an edit whose push has
    // not been acknowledged yet would be silently dropped. Applied here so
    // all three callers (`adjustCount`, `adjustValue`, `setNote`) inherit it.
    final dirtyPatch = patch.copyWith(dirty: const Value(true));
    final merged = existing.copyWithCompanion(dirtyPatch);
    return writeAndNotify<void>(
      entity: entityName,
      rowId: existing.id,
      op: SyncOp.upsert,
      payload: _payloadOf(merged),
      write: () => (db.update(
        db.habitLogs,
      )..where((l) => l.id.equals(existing.id)))
          .write(dirtyPatch),
    );
  }

  /// The full-row wire payload for [row] using the server's exact
  /// snake_case field names (ADR-0002 §3) — see the equivalent note on
  /// `HabitRepository._payloadOf`: built by hand rather than via Drift's
  /// generated (camelCase) `HabitLog.toJson()`, since `sync_engine.dart`
  /// forwards an outbox payload to the server unmodified.
  Map<String, dynamic> _payloadOf(HabitLog row) => {
        'id': row.id,
        'user_id': row.userId,
        'habit_id': row.habitId,
        // `date` is the natural-key DATE column (ADR-0002 rule 9), not a
        // timestamp: a full datetime string is rejected as `schema_invalid`.
        'date': toWireDate(row.date),
        'count': row.count,
        'value': row.value,
        'note': row.note,
        // Millisecond precision per ADR-0002 rule 13.
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
Expression<bool> _userIdMatches($HabitLogsTable t, String? userId) =>
    userId == null ? const Constant(true) : t.userId.equals(userId);
