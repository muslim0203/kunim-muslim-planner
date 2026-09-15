/// Applies the server's sync answers to the local database. This file
/// deliberately contains NO merge logic — ADR-0002 "Konflikt matritsasi":
/// merge decisions are made ONLY by `apps/api/app/modules/sync/merge.py`.
///
/// What this file does with each push [SyncPushResult]:
/// - `applied`  -> the local row already matches; just record the new
///   `server_version` and clear `dirty` (unless a newer, not-yet-sent local
///   edit is already queued for the same row), then acknowledge the outbox
///   entry.
/// - `conflict` -> unconditionally overwrite the local row with
///   `server_row` (the server's full, authoritative state), then
///   acknowledge the outbox entry too (ADR: both `applied` and `conflict`
///   remove the outbox entry — a conflict is not retried).
/// - `rejected` -> act on the closed `reason` enum (ADR-0002 §3 table):
///   `updated_at_in_future` re-stamps and re-queues; `unknown_entity` /
///   `foreign_user` / `readonly_entity` drop the entry and log;
///   `schema_invalid` / `payload_too_large` are left in the outbox with
///   `last_error` set (surfaced to Settings -> Diagnostics later) rather
///   than silently dropped or blindly retried.
///
/// Pulled rows ([SyncPullRow]) are applied the same way as a `conflict`'s
/// `server_row`: unconditional overwrite, `dirty = false`, no outbox entry
/// created (`writeFromServer` — see `core/db/base_repository.dart`).
///
/// Entity <-> local table mapping: only the tables that exist in
/// `core/db/app_database.dart` can be applied here. An `entity` the server
/// knows about but this client build does not yet have a table for is
/// skipped (logged, not thrown) — forward-compatible with a server that has
/// more entities registered than a given client release implements.
///
/// Wire rows are NOT the local column shape, so each adapter declares how to
/// convert one ([_EntityAdapter.fromWire]) before Drift decodes it: server
/// `DATE` values, renamed fields (`habits.schedule` -> `frequency`), enum
/// names stored as indexes (`tasks.priority`) and JSON lists kept in text
/// columns.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/base_repository.dart';
import '../db/tables/tasks_table.dart' show TaskPriority;
import 'outbox.dart';
import 'sync_models.dart';

/// Concrete [SyncableRepository] subclass that exists only to reach the
/// protected-by-convention `writeFromServer` escape hatch from within
/// `core/sync` — exactly the caller `base_repository.dart` documents it
/// for. Holds no state of its own beyond the [AppDatabase] it wraps.
class _SyncEngineWrites extends SyncableRepository {
  _SyncEngineWrites(super.db);
}

typedef _WireToLocal = Map<String, dynamic> Function(Map<String, dynamic>);

/// One registered local entity: how to turn the server's snake_case wire
/// row into a typed Drift row and write it, and how to purge it during a
/// full resync. Kept private and generic so adding an entity is a single
/// map entry, not a new class.
class _EntityAdapter<D extends Insertable<D>, T extends Table> {
  const _EntityAdapter({
    required this.tableName,
    required this.table,
    required this.fromJson,
    this.fromWire = _unchanged,
  });

  /// SQL table name (matches the entity string exactly for every table
  /// declared with `SyncColumns`).
  final String tableName;
  final TableInfo<T, D> Function(AppDatabase db) table;
  final D Function(Map<String, dynamic> json) fromJson;

  /// Converts a (copied) wire row into the local column shape, still in
  /// snake_case.
  final _WireToLocal fromWire;

  /// Full-row upsert from a server wire row. [dirty] is set explicitly
  /// because the wire never carries it.
  Future<void> upsertWire(
    AppDatabase db,
    Map<String, dynamic> wireRow, {
    required bool dirty,
  }) {
    final local = fromWire(Map<String, dynamic>.from(wireRow));
    final camel = _snakeToCamelJson(local)..['dirty'] = dirty;
    return db.into(table(db)).insertOnConflictUpdate(fromJson(camel));
  }
}

Map<String, dynamic> _unchanged(Map<String, dynamic> row) => row;

final RegExp _wireDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Builds a [_EntityAdapter.fromWire] from declarative parts.
///
/// - [renames]: wire field -> local column, applied first.
/// - [dates]: server `DATE` fields (`2026-09-12`). Drift would parse a bare
///   date as LOCAL midnight, so a pulled row would never compare equal to
///   the same day written on this device (which stores UTC midnight, see
///   `LocalDay.toUtcMidnight`); they become explicit UTC midnight instead.
/// - [jsonText]: fields that are JSON objects/lists on the wire but text
///   columns locally.
_WireToLocal _wire({
  Map<String, String> renames = const {},
  List<String> dates = const [],
  List<String> jsonText = const [],
  void Function(Map<String, dynamic> row)? also,
}) {
  return (row) {
    renames.forEach((wireName, localName) {
      if (row.containsKey(wireName)) row[localName] = row.remove(wireName);
    });
    for (final field in dates) {
      final value = row[field];
      if (value is String && _wireDatePattern.hasMatch(value)) {
        row[field] = '${value}T00:00:00.000Z';
      }
    }
    for (final field in jsonText) {
      final value = row[field];
      if (value is List || value is Map) row[field] = jsonEncode(value);
    }
    also?.call(row);
    return row;
  };
}

/// `tasks.priority` is the enum NAME on the wire and its index locally.
void _taskPriorityFromWire(Map<String, dynamic> row) {
  final priority = row['priority'];
  if (priority is String) {
    row['priority'] = TaskPriority.values
        .firstWhere(
          (value) => value.name == priority,
          orElse: () => TaskPriority.medium,
        )
        .index;
  }
}

final Map<String, _EntityAdapter<dynamic, dynamic>> _entityAdapters = {
  'task_categories': _EntityAdapter<TaskCategory, $TaskCategoriesTable>(
    tableName: 'task_categories',
    table: (db) => db.taskCategories,
    fromJson: TaskCategory.fromJson,
  ),
  'tasks': _EntityAdapter<Task, $TasksTable>(
    tableName: 'tasks',
    table: (db) => db.tasks,
    fromJson: Task.fromJson,
    fromWire: _wire(dates: const ['due_date'], also: _taskPriorityFromWire),
  ),
  'calendar_events': _EntityAdapter<CalendarEvent, $CalendarEventsTable>(
    tableName: 'calendar_events',
    table: (db) => db.calendarEvents,
    fromJson: CalendarEvent.fromJson,
  ),
  'habits': _EntityAdapter<Habit, $HabitsTable>(
    tableName: 'habits',
    table: (db) => db.habits,
    fromJson: Habit.fromJson,
    // The local `frequency` column stores the schedule object as JSON text
    // (`HabitSchedule.toJson`), and `target_count` is `target` on the wire.
    fromWire: _wire(
      renames: const {'schedule': 'frequency', 'target': 'target_count'},
      jsonText: const ['frequency'],
    ),
  ),
  'habit_logs': _EntityAdapter<HabitLog, $HabitLogsTable>(
    tableName: 'habit_logs',
    table: (db) => db.habitLogs,
    fromJson: HabitLog.fromJson,
    fromWire: _wire(dates: const ['date']),
  ),
  'goals': _EntityAdapter<Goal, $GoalsTable>(
    tableName: 'goals',
    table: (db) => db.goals,
    fromJson: Goal.fromJson,
    fromWire: _wire(dates: const ['target_date']),
  ),
  'milestones': _EntityAdapter<Milestone, $MilestonesTable>(
    tableName: 'milestones',
    table: (db) => db.milestones,
    fromJson: Milestone.fromJson,
    fromWire: _wire(dates: const ['target_date']),
  ),
  'preferences': _EntityAdapter<Preference, $PreferencesTable>(
    tableName: 'preferences',
    table: (db) => db.preferences,
    fromJson: Preference.fromJson,
  ),
  'mood_logs': _EntityAdapter<MoodLog, $MoodLogsTable>(
    tableName: 'mood_logs',
    table: (db) => db.moodLogs,
    fromJson: MoodLog.fromJson,
    fromWire: _wire(dates: const ['date'], jsonText: const ['tags']),
  ),
  'sleep_logs': _EntityAdapter<SleepLog, $SleepLogsTable>(
    tableName: 'sleep_logs',
    table: (db) => db.sleepLogs,
    fromJson: SleepLog.fromJson,
    fromWire: _wire(dates: const ['date']),
  ),
  'health_logs': _EntityAdapter<HealthLog, $HealthLogsTable>(
    tableName: 'health_logs',
    table: (db) => db.healthLogs,
    fromJson: HealthLog.fromJson,
    fromWire: _wire(dates: const ['date']),
  ),
  'family_logs': _EntityAdapter<FamilyLog, $FamilyLogsTable>(
    tableName: 'family_logs',
    table: (db) => db.familyLogs,
    fromJson: FamilyLog.fromJson,
    fromWire: _wire(dates: const ['date'], jsonText: const ['activities']),
  ),
  'prayer_logs': _EntityAdapter<PrayerLog, $PrayerLogsTable>(
    tableName: 'prayer_logs',
    table: (db) => db.prayerLogs,
    fromJson: PrayerLog.fromJson,
    fromWire: _wire(dates: const ['date']),
  ),
};

/// Entities this client build can apply pulled/conflict rows for — used by
/// `full_resync_required` handling to know which local tables to purge.
/// Exposed as a plain list (not the adapter map) so nothing outside this
/// file depends on `_EntityAdapter`.
List<String> get knownSyncEntities => _entityAdapters.keys.toList(
      growable: false,
    );

void _log(String message) {
  // Never logs payload/token contents — only entity/rowId/reason, which
  // are not user secrets. See task constraint "never log tokens or
  // payload contents".
  developer.log(message, name: 'sync.conflict');
}

String _snakeToCamel(String snake) {
  if (!snake.contains('_')) return snake;
  final parts = snake.split('_');
  final buffer = StringBuffer(parts.first);
  for (final part in parts.skip(1)) {
    if (part.isEmpty) continue;
    buffer
      ..write(part[0].toUpperCase())
      ..write(part.substring(1));
  }
  return buffer.toString();
}

Map<String, dynamic> _snakeToCamelJson(Map<String, dynamic> json) {
  return json.map((key, value) => MapEntry(_snakeToCamel(key), value));
}

/// Formats [dt] as RFC 3339 UTC with exactly millisecond precision
/// (`2026-09-12T08:15:30.123Z`), matching ADR-0002 rule 13.
String toRfc3339Millis(DateTime dt) {
  final truncated = DateTime.fromMillisecondsSinceEpoch(
    dt.toUtc().millisecondsSinceEpoch,
    isUtc: true,
  );
  return truncated.toIso8601String();
}

/// Formats [dt] as a calendar date only (`2026-09-12`).
///
/// Several wire fields are `DATE` on the server (`tasks.due_date`,
/// `goals.target_date`, `milestones.target_date`, the daily logs' `date`)
/// while the local Drift columns are `DateTimeColumn`. Sending a full
/// timestamp for one of those is rejected outright as `schema_invalid`, so
/// every payload builder must funnel date-typed fields through here.
///
/// Uses the instant's **UTC** calendar fields, matching `toRfc3339Millis`, so
/// a row's date and its timestamps can never disagree about which day it is.
String toWireDate(DateTime dt) {
  final utc = dt.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-$month-$day';
}

Future<bool> _hasPendingOutbox(
  AppDatabase db,
  String entity,
  String rowId,
) async {
  final rows = await (db.select(db.syncOutbox)
        ..where((t) => t.entity.equals(entity) & t.rowId.equals(rowId)))
      .get();
  return rows.isNotEmpty;
}

/// Applies a server-derived row (a pull row, or a `conflict`'s
/// `server_row`) to the matching local table via [_SyncEngineWrites
/// .writeFromServer] — no outbox entry is created, so this can never loop.
/// Unknown entities are skipped (logged) rather than throwing.
Future<void> _applyEntityRow(
  AppDatabase db,
  String entity,
  Map<String, dynamic> wireRow, {
  required bool dirty,
}) async {
  final adapter = _entityAdapters[entity];
  if (adapter == null) {
    _log('skip unknown entity "$entity" (row not applied locally)');
    return;
  }
  final writes = _SyncEngineWrites(db);
  await writes.writeFromServer(
    () => adapter.upsertWire(db, wireRow, dirty: dirty),
  );
}

/// Applies one full pulled page inside a single local transaction, per
/// ADR-0002 rule 7 — the caller (`sync_engine.dart`) must only persist the
/// new cursor after this completes without throwing.
Future<void> applyPulledPage(AppDatabase db, List<SyncPullRow> rows) async {
  final writes = _SyncEngineWrites(db);
  await writes.writeFromServer(() async {
    for (final row in rows) {
      final adapter = _entityAdapters[row.entity];
      if (adapter == null) {
        _log('skip unknown entity "${row.entity}" during pull apply');
        continue;
      }

      final rowId = row.row['id'];
      // A locally-dirty row with an unpushed outbox entry must NOT be
      // overwritten by a pulled row: `pull` can be in flight while the user
      // is editing, and blindly replacing the row (and clearing `dirty`)
      // makes that edit vanish from the UI. The push-apply path
      // (`applyPushResults`) has always guarded this; pull did not.
      //
      // Skipping is safe: the pending outbox entry is still pushed on the
      // next cycle, and the server's answer decides the winner -- which is
      // exactly ADR-0002's "merge lives only on the server".
      if (rowId is String && await _hasPendingOutbox(db, row.entity, rowId)) {
        _log(
          'keep local dirty row ${row.entity}/$rowId during pull apply '
          '(unpushed outbox entry pending)',
        );
        continue;
      }

      // Deliberately NOT wrapped in a per-row try/catch. A row that cannot
      // be written must fail the whole page so the cursor stays put
      // (`sync_engine_pull_test.dart`: "cursor does not advance when
      // applying a page throws") -- swallowing the error would advance past
      // the row and lose it for ever, since pull never re-delivers it.
      //
      // The deadlock this used to cause is fixed at its root instead: the
      // log tables have no table-level UNIQUE on the natural key (see
      // `HabitLogs`), so a rule-14 tombstone sharing a natural key is
      // storable. If some other unwritable row ever appears, the page does
      // stall by design -- that needs a real quarantine/dead-letter design
      // rather than a silent drop here.
      await adapter.upsertWire(db, row.row, dirty: false);
    }
  });
}

/// Deletes every locally-clean (`dirty = 0`) row across all known sync
/// tables — step 2 of the ADR-0002 §4 mandatory full-resync recovery.
/// Rows with `dirty = 1` (an unpushed local edit) are preserved: losing an
/// unsynced edit here would be the worst possible bug (task T-204 brief).
Future<void> purgeCleanRows(AppDatabase db) async {
  final writes = _SyncEngineWrites(db);
  await writes.writeFromServer(() async {
    for (final adapter in _entityAdapters.values) {
      await db.customStatement(
        'DELETE FROM ${adapter.tableName} WHERE dirty = 0',
      );
    }
  });
}

/// Result of applying one push batch's results: which outbox seqs still
/// need attention on the next cycle (`schema_invalid`/`payload_too_large`
/// rejections, left in place with `last_error` set) versus a hard
/// transport-level failure the caller should retry as a whole.
class PushApplyOutcome {
  const PushApplyOutcome(
      {required this.appliedOrConflicted,
      required this.rejectedTerminally,
      required this.requeued});

  final int appliedOrConflicted;
  final int rejectedTerminally;
  final int requeued;
}

/// Applies every result of one push batch: acknowledges `applied`/
/// `conflict` outbox entries, overwrites local rows on `conflict`, and acts
/// on each `rejected` reason (ADR-0002 §3 table). [sentBatch] must be the
/// exact [OutboxEntry] list the batch was built from (needed to rebuild a
/// fresh payload on `updated_at_in_future`; results alone don't carry the
/// original payload).
Future<PushApplyOutcome> applyPushResults({
  required AppDatabase db,
  required OutboxDao outboxDao,
  required List<OutboxEntry> sentBatch,
  required List<SyncPushResult> results,
  required DateTime Function() now,
}) async {
  final entryBySeq = {for (final e in sentBatch) e.seq: e};
  var appliedOrConflicted = 0;
  var rejectedTerminally = 0;
  var requeued = 0;

  for (final result in results) {
    switch (result) {
      case SyncPushResultApplied(
          :final clientSeq,
          :final entity,
          :final rowId,
          :final serverVersion,
        ):
        await outboxDao.acknowledge([clientSeq]);
        final stillDirty = await _hasPendingOutbox(db, entity, rowId);
        final adapter = _entityAdapters[entity];
        if (adapter != null) {
          // Only the bookkeeping columns change here — the local row
          // already matches what the server accepted, and a targeted
          // update (rather than a full-row overwrite from the possibly
          // now-stale outbox payload) cannot clobber a newer local edit
          // that may already be sitting in the table.
          await db.customStatement(
            'UPDATE ${adapter.tableName} SET server_version = ?, '
            'dirty = ? WHERE id = ?',
            [serverVersion, stillDirty ? 1 : 0, rowId],
          );
        }
        appliedOrConflicted++;

      case SyncPushResultConflict(
          :final clientSeq,
          :final entity,
          :final rowId,
          :final serverRow,
        ):
        await outboxDao.acknowledge([clientSeq]);
        final stillDirty = await _hasPendingOutbox(db, entity, rowId);
        await _applyEntityRow(db, entity, serverRow, dirty: stillDirty);
        appliedOrConflicted++;

      case SyncPushResultRejected(
          :final clientSeq,
          :final entity,
          :final rowId,
          :final reason,
        ):
        switch (reason) {
          case 'updated_at_in_future':
            final entry = entryBySeq[clientSeq];
            if (entry == null) {
              await outboxDao.recordFailure(clientSeq, error: reason);
              break;
            }
            await _requeueWithFreshTimestamp(db, outboxDao, entry, now());
            requeued++;

          case 'unknown_entity':
          case 'foreign_user':
          case 'readonly_entity':
            await outboxDao.acknowledge([clientSeq]);
            _log(
              'dropping outbox entry entity=$entity row=$rowId '
              'reason=$reason',
            );
            rejectedTerminally++;

          case 'schema_invalid':
          case 'payload_too_large':
          default:
            // ADR: left in the outbox with last_error for diagnostics,
            // never silently dropped. Whether it should also stop being
            // re-sent every cycle is a UI/diagnostics-screen concern this
            // task does not own; recording the failure at least makes it
            // visible and keeps `attempts` accurate.
            await outboxDao.recordFailure(clientSeq, error: reason);
            _log(
              'outbox entry needs attention entity=$entity row=$rowId '
              'reason=$reason',
            );
            rejectedTerminally++;
        }
    }
  }

  return PushApplyOutcome(
    appliedOrConflicted: appliedOrConflicted,
    rejectedTerminally: rejectedTerminally,
    requeued: requeued,
  );
}

/// ADR-0002 §3 `updated_at_in_future` handling: re-stamp the row's
/// `updated_at` to [now] (both locally and in a fresh outbox entry) and
/// re-queue it. The old outbox entry is removed and a new one inserted
/// with a new `seq`, so it goes out again at the back of the queue.
Future<void> _requeueWithFreshTimestamp(
  AppDatabase db,
  OutboxDao outboxDao,
  OutboxEntry entry,
  DateTime now,
) async {
  final freshWireRow = Map<String, dynamic>.from(entry.payload)
    ..['updated_at'] = toRfc3339Millis(now);
  final writes = _SyncEngineWrites(db);
  await writes.writeFromServer(() async {
    // Not a user-driven write, so `writeWithOutbox` (which would reject a
    // `dirty` key and is meant for feature repositories) does not apply
    // here; this re-implements its two-writes-in-one-transaction shape by
    // hand for the engine's own internal requeue.
    await outboxDao.acknowledge([entry.seq]);
    final adapter = _entityAdapters[entry.entity];
    if (adapter == null) {
      _log('skip unknown entity "${entry.entity}" (row not applied locally)');
    } else {
      await adapter.upsertWire(db, freshWireRow, dirty: true);
    }
    await db.into(db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            entity: entry.entity,
            rowId: entry.rowId,
            op: entry.op.name,
            payload: jsonEncode(syncPayload(freshWireRow)),
          ),
        );
  });
}
