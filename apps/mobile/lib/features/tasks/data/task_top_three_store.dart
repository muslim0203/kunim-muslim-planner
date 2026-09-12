/// Local-only persistence for the manual Top-3 pin list
/// (`domain/top_three_selection.dart`).
///
/// This is deliberately backed by the generic `KeyValue` table
/// (`core/db/app_database.dart`) instead of a new column/table, and is
/// deliberately NOT written through `SyncableRepository.writeWithOutbox`:
///
/// - `core/db/app_database.dart`'s own doc comment describes `KeyValue`
///   as exactly this: "local-only flags and settings that do not warrant
///   their own table (e.g. onboarding completion, last sync cursor...)".
///   The manual Top-3 pin list is the same kind of thing — a per-device
///   UI preference, not user *content*.
/// - `key_value` is not a sync entity: it has none of the `SyncColumns`,
///   is absent from ADR-0002's sync table list, and is not part of
///   `SYNC_ENTITIES` on the server. Routing a write to it through
///   `writeWithOutbox` would queue an outbox entry the server can only
///   answer with `rejected`/`unknown_entity` — worse than not syncing it
///   at all. Plain reads/writes to a genuinely local-only table are the
///   documented exception to "never write a Drift table directly";
///   `writeWithOutbox`'s own contract is specifically about *syncable*
///   tables.
/// - Consequently the Top-3 selection does **not** sync across devices in
///   phase 2, matching the plan's "Home'da Top-3 (qo'lda)" phase-2 scope.
///   If a later phase needs it to sync, that requires an actual `core/db`
///   schema change (e.g. a rank/flag column on `Tasks`, or a small new
///   sync table) — out of scope here; see the task report's escalation
///   note.
library;

import 'dart:convert';

import 'package:kunim/core/db/app_database.dart';

import '../domain/top_three_selection.dart';

class TaskTopThreeStore {
  TaskTopThreeStore(this.db);

  final AppDatabase db;

  /// `KeyValue.key` for the pin list. Scoped to this feature by the
  /// `tasks.` prefix, mirroring how `preferences`-style keys are usually
  /// namespaced.
  static const _key = 'tasks.top_three_task_ids';

  /// Reactive read of the current selection. Emits `TopThreeSelection`
  /// (never a raw nullable row) — an absent `KeyValue` row decodes to
  /// `TopThreeSelection.empty`, so callers never need a null check.
  Stream<TopThreeSelection> watch() {
    final query = db.select(db.keyValue)..where((t) => t.key.equals(_key));
    return query.watchSingleOrNull().map(_decode);
  }

  Future<TopThreeSelection> read() async {
    final query = db.select(db.keyValue)..where((t) => t.key.equals(_key));
    final row = await query.getSingleOrNull();
    return _decode(row);
  }

  Future<void> pin(String taskId) => _update((s) => s.withPinned(taskId));

  Future<void> unpin(String taskId) => _update((s) => s.withUnpinned(taskId));

  /// Replaces the selection outright, e.g. after a drag-and-drop reorder
  /// screen produces a full new ordering.
  Future<void> replace(List<String> orderedTaskIds) =>
      _save(TopThreeSelection(orderedTaskIds));

  Future<void> _update(
    TopThreeSelection Function(TopThreeSelection current) transform,
  ) async {
    final current = await read();
    await _save(transform(current));
  }

  Future<void> _save(TopThreeSelection selection) {
    return db.into(db.keyValue).insertOnConflictUpdate(
          KeyValueCompanion.insert(
            key: _key,
            value: jsonEncode(selection.taskIds),
          ),
        );
  }

  TopThreeSelection _decode(KeyValueData? row) {
    if (row == null) return TopThreeSelection.empty;
    final decoded = jsonDecode(row.value) as List<dynamic>;
    return TopThreeSelection(decoded.cast<String>());
  }
}
