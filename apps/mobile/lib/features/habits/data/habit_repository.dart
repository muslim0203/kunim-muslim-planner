/// Data access for the `Habits` table (habit *definitions* — see
/// `data/habit_log_repository.dart` for a habit's daily completions).
///
/// Every mutation goes through [SyncableRepository.writeWithOutbox] (the
/// only sanctioned write path — see that method's doc) and, on success,
/// [HabitLocalWriteHook.writeAndNotify] calls `onLocalWrite()`. Reads are
/// reactive Drift `watch()` streams, per `AppDatabase`'s own doc ("prefer
/// Drift `watch()` streams").
///
/// `habits` is plain LWW + soft delete on the server (ADR-0002
/// conflict-matrix rule 20) — no merge subtlety here like `habit_logs`
/// has; see that repository's doc for rule 9/14.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';
import '../../../core/sync/conflict.dart' show toRfc3339Millis;
import '../domain/habit_schedule.dart';
import '../domain/local_day.dart';
import 'habit_local_write_hook.dart';

/// A [Habit] paired with its (optional) log for one specific day — the
/// read model `application/habits_today_provider.dart` builds "habits for
/// today" from. [log] is `null` when the habit has no log for that day
/// yet (not done, or never logged), which is the normal case, not an
/// error.
class HabitWithDayLog {
  const HabitWithDayLog({required this.habit, required this.log});

  final Habit habit;
  final HabitLog? log;
}

class HabitRepository extends SyncableRepository with HabitLocalWriteHook {
  HabitRepository(super.db, {required this.onLocalWrite});

  @override
  final void Function() onLocalWrite;

  static const String entityName = 'habits';

  // --- Reads (reactive) -------------------------------------------------

  /// Active (non-archived) habits, oldest first. [userId] narrows to one
  /// user's habits once auth exists (Phase 0: usually `null`, meaning "no
  /// user filter").
  Stream<List<Habit>> watchActiveHabits({String? userId}) {
    final query = db.select(db.habits)
      ..where((h) => h.deletedAt.isNull())
      ..orderBy([(h) => OrderingTerm.asc(h.createdAt)]);
    if (userId != null) {
      query.where((h) => h.userId.equals(userId));
    }
    return query.watch();
  }

  /// A single habit by id, or `null` if it doesn't exist or was archived.
  Stream<Habit?> watchHabit(String id) {
    final query = db.select(db.habits)
      ..where((h) => h.id.equals(id) & h.deletedAt.isNull());
    return query.watchSingleOrNull();
  }

  /// Every active habit, each paired with its log for [day] if one exists
  /// (`null` otherwise — see [HabitWithDayLog]). Filtering *which* of
  /// these are actually due on [day] is the application layer's job
  /// (`HabitSchedule.fromJson(habit.frequency).isScheduledOn(day)`) — this
  /// method only joins the data, it does not interpret the schedule.
  Stream<List<HabitWithDayLog>> watchActiveHabitsWithLogOnDay(
    LocalDay day, {
    String? userId,
  }) {
    final query = db.select(db.habits).join([
      leftOuterJoin(
        db.habitLogs,
        db.habitLogs.habitId.equalsExp(db.habits.id) &
            db.habitLogs.date.equals(day.toUtcMidnight()) &
            db.habitLogs.deletedAt.isNull(),
      ),
    ])
      ..where(db.habits.deletedAt.isNull());
    if (userId != null) {
      query.where(db.habits.userId.equals(userId));
    }
    return query.watch().map(
          (rows) => rows
              .map(
                (row) => HabitWithDayLog(
                  habit: row.readTable(db.habits),
                  log: row.readTableOrNull(db.habitLogs),
                ),
              )
              .toList(growable: false),
        );
  }

  Future<Habit?> findById(String id) {
    return (db.select(
      db.habits,
    )..where((h) => h.id.equals(id)))
        .getSingleOrNull();
  }

  // --- Mutations ----------------------------------------------------------

  /// Creates a new habit and returns its generated id.
  Future<String> createHabit({
    String? userId,
    required String title,
    String? description,
    HabitSchedule schedule = HabitSchedule.defaultSchedule,
    int targetCount = 1,
    String? color,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final scheduleJson = schedule.toJson();

    await writeAndNotify<void>(
      entity: entityName,
      rowId: id,
      op: SyncOp.upsert,
      payload: {
        'id': id,
        'user_id': userId,
        'created_at': toRfc3339Millis(now),
        'updated_at': toRfc3339Millis(now),
        'deleted_at': null,
        'server_version': 0,
        'title': title,
        'description': description,
        // Wire field is `schedule` (a JSON object), not `frequency` (the
        // local column, which holds the same JSON as a string).
        'schedule': _scheduleObject(scheduleJson),
        'target': targetCount,
        'color': color,
      },
      write: () => db.into(db.habits).insert(
            HabitsCompanion.insert(
              id: Value(id),
              userId: Value(userId),
              createdAt: Value(now),
              updatedAt: Value(now),
              title: title,
              description: Value(description),
              frequency: Value(scheduleJson),
              targetCount: Value(targetCount),
              color: Value(color),
            ),
          ),
    );
    return id;
  }

  /// Patches an existing habit. Any field left `Value.absent()` (the
  /// default) is left unchanged; pass `Value(null)` to explicitly clear a
  /// nullable field (e.g. `description: Value(null)`).
  Future<void> updateHabit({
    required String id,
    Value<String> title = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<HabitSchedule> schedule = const Value.absent(),
    Value<int> targetCount = const Value.absent(),
    Value<String?> color = const Value.absent(),
  }) async {
    final current = await findById(id);
    if (current == null) {
      throw StateError('Cannot update habit $id: it does not exist.');
    }
    final now = DateTime.now().toUtc();
    final patch = HabitsCompanion(
      updatedAt: Value(now),
      // Re-arm `dirty`: a full resync deletes `dirty = 0` rows, so an edit
      // whose push has not landed yet would be silently dropped.
      dirty: const Value(true),
      title: title,
      description: description,
      frequency: schedule.present
          ? Value(schedule.value.toJson())
          : const Value.absent(),
      targetCount: targetCount,
      color: color,
    );
    final merged = current.copyWithCompanion(patch);

    await writeAndNotify<void>(
      entity: entityName,
      rowId: id,
      op: SyncOp.upsert,
      payload: _payloadOf(merged),
      write: () =>
          (db.update(db.habits)..where((h) => h.id.equals(id))).write(patch),
    );
  }

  /// Soft-deletes (archives) a habit. A no-op if it does not exist or is
  /// already archived.
  Future<void> archiveHabit(String id) async {
    final current = await findById(id);
    if (current == null || current.deletedAt != null) return;

    final now = DateTime.now().toUtc();
    final patch = HabitsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      dirty: const Value(true),
    );
    final merged = current.copyWithCompanion(patch);

    await writeAndNotify<void>(
      entity: entityName,
      rowId: id,
      op: SyncOp.delete,
      payload: _payloadOf(merged),
      write: () =>
          (db.update(db.habits)..where((h) => h.id.equals(id))).write(patch),
    );
  }

  /// The full-row wire payload for [row], using the server's exact
  /// snake_case field names (ADR-0002 §3) — deliberately built by hand
  /// rather than via Drift's generated `Habit.toJson()`, which emits
  /// camelCase Dart field names instead (`sync_engine.dart` forwards an
  /// outbox entry's payload to the server byte-for-byte, with no case
  /// conversion on push).
  Map<String, dynamic> _payloadOf(Habit row) => {
        'id': row.id,
        'user_id': row.userId,
        // Millisecond precision, not `toIso8601String()`'s microseconds:
        // ADR-0002 rule 13, and the server echoes milliseconds back.
        'created_at': toRfc3339Millis(row.createdAt),
        'updated_at': toRfc3339Millis(row.updatedAt),
        'deleted_at':
            row.deletedAt == null ? null : toRfc3339Millis(row.deletedAt!),
        'server_version': row.serverVersion,
        'title': row.title,
        'description': row.description,
        // The local `frequency` column stores `HabitSchedule.toJson()` as a
        // STRING; the wire field is `schedule`, a JSON OBJECT (JSONB on the
        // server). Decode rather than pass the string through, or the row is
        // rejected as `schema_invalid`.
        'schedule': _scheduleObject(row.frequency),
        'target': row.targetCount,
        'color': row.color,
      };

  /// Decodes the locally stored schedule string into the wire object.
  ///
  /// Falls back to the default schedule's object form for anything
  /// unparseable, exactly as `HabitSchedule.fromJson` does for reads, so a
  /// corrupt local value degrades instead of blocking the whole outbox.
  static Map<String, dynamic> _scheduleObject(String raw) {
    final decoded = jsonDecode(HabitSchedule.fromJson(raw).toJson());
    return (decoded as Map).cast<String, dynamic>();
  }
}
