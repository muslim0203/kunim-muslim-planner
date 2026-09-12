/// Data-layer access to the `goals` table (ADR-0002 §1 /
/// `docs/sync-conflict-matrix.md` rule 18: plain last-write-wins, no
/// natural-key merge). Every mutation goes through
/// [SyncableRepository.writeWithOutbox] so the row write and its outbox
/// entry are always the same local transaction (`CLAUDE.md` rule 2), and
/// every successful mutation calls [onLocalWrite] afterwards — wired to
/// `syncTriggerSchedulerProvider.onLocalWrite()` by
/// `application/goals_providers.dart` — so the "N local writes" sync
/// trigger (ADR-0002 §2) actually fires.
///
/// [Goal.progressPercent] is passed straight through on every write with
/// no clamping/floor logic: rule 18 explicitly makes it a plain
/// last-write-wins field that may legitimately go backwards (a goal can
/// be un-completed by the user or by a later-losing device), so this
/// repository must never "protect" it from decreasing.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';
import '../../../core/sync/conflict.dart' show toRfc3339Millis, toWireDate;

const _uuid = Uuid();

class GoalRepository extends SyncableRepository {
  GoalRepository(
    super.db, {
    this.onLocalWrite,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  /// Called once after every successful mutation below, never when a
  /// write throws. `null` in a plain repository test that does not care
  /// about the sync trigger.
  final void Function()? onLocalWrite;
  final DateTime Function() _now;

  /// All non-deleted goals: ones with a [Goal.targetDate] first (closest
  /// deadline first), then ones without a target date, most recently
  /// created first.
  Stream<List<Goal>> watchActive() {
    final query = db.select(db.goals)
      ..where((g) => g.deletedAt.isNull())
      ..orderBy([
        (g) => OrderingTerm(expression: g.targetDate.isNull()),
        (g) => OrderingTerm(expression: g.targetDate),
        (g) => OrderingTerm(expression: g.createdAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// A single goal by id, or `null` if it does not exist locally — either
  /// never created on this device, or (per
  /// `docs/sync-conflict-matrix.md`) not yet pulled from the server.
  /// Deliberately does NOT filter out a soft-deleted row: a detail screen
  /// needs to know a goal was deleted, not have it silently look
  /// "not found".
  Stream<Goal?> watchById(String id) {
    final query = db.select(db.goals)..where((g) => g.id.equals(id));
    return query.watchSingleOrNull();
  }

  Future<Goal> createGoal({
    required String title,
    String? description,
    DateTime? targetDate,
    int progressPercent = 0,
    String? userId,
  }) {
    final now = _now();
    final row = Goal(
      id: _uuid.v4(),
      userId: userId,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      serverVersion: 0,
      dirty: true,
      title: title,
      description: description,
      targetDate: targetDate,
      progressPercent: progressPercent,
    );
    return _persist(row);
  }

  /// Updates fields of an existing goal. The nullable column
  /// ([description]) uses Drift's `Value` wrapper so a caller can
  /// distinguish "leave unchanged" ([Value.absent]) from "explicitly
  /// clear" (`Value(null)`) — the same convention Drift's own generated
  /// `Goal.copyWith` uses. [title]/[targetDate]/[progressPercent] are
  /// plain nullable params where `null` means "leave unchanged"; passing
  /// `null` for [targetDate] here cannot express "clear the target date"
  /// — pass [clearTargetDate] for that.
  ///
  /// Throws [StateError] if [id] does not exist locally.
  Future<Goal> updateGoal({
    required String id,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? targetDate,
    bool clearTargetDate = false,
    int? progressPercent,
  }) async {
    final existing = await _require(id);
    final updated = existing.copyWith(
      title: title,
      description: description,
      targetDate: clearTargetDate
          ? const Value(null)
          : (targetDate == null ? const Value.absent() : Value(targetDate)),
      progressPercent: progressPercent,
      updatedAt: _now(),
    );
    return _persist(updated);
  }

  /// Convenience wrapper over [updateGoal] for the common "just change the
  /// progress number" action. Deliberately accepts any `int`, including
  /// one lower than the current value — see the class doc.
  Future<Goal> updateProgress(
      {required String id, required int progressPercent}) {
    return updateGoal(id: id, progressPercent: progressPercent);
  }

  /// Soft-deletes a goal (sets `deleted_at`), per sync-conflict-matrix
  /// rule 18 (LWW + soft delete). A no-op if the goal is already deleted
  /// or does not exist locally — deleting is idempotent from a caller's
  /// point of view.
  Future<void> deleteGoal(String id) async {
    final existing = await (db.select(db.goals)..where((g) => g.id.equals(id)))
        .getSingleOrNull();
    if (existing == null || existing.deletedAt != null) return;

    final now = _now();
    final updated = existing.copyWith(deletedAt: Value(now), updatedAt: now);
    await writeWithOutbox<void>(
      entity: 'goals',
      rowId: id,
      op: SyncOp.delete,
      payload: _payloadOf(updated),
      write: () => db.update(db.goals).replace(updated),
    );
    onLocalWrite?.call();
  }

  Future<Goal> _require(String id) async {
    final existing = await (db.select(db.goals)..where((g) => g.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      throw StateError('Goal not found: $id');
    }
    return existing;
  }

  /// Upserts [row] locally (insert if new, full-column update if it
  /// already exists — either way the row now matches [row] exactly) and
  /// queues the same full row as the outbox payload.
  Future<Goal> _persist(Goal row) async {
    // See `MilestoneRepository._persist`: `dirty` must be re-armed on every
    // local write, or a full resync deletes an edit that has not been pushed.
    final pending = row.copyWith(dirty: true);
    final result = await writeWithOutbox<Goal>(
      entity: 'goals',
      rowId: pending.id,
      op: SyncOp.upsert,
      payload: _payloadOf(pending),
      write: () async {
        await db.into(db.goals).insertOnConflictUpdate(pending);
        return pending;
      },
    );
    onLocalWrite?.call();
    return result;
  }

  /// The `goals` wire row (ADR-0002 rule 18).
  ///
  /// Hand-built snake_case, not Drift's `toJson()` (which emits `userId`,
  /// `targetDate`, ... and a client-only `dirty`): the server's row schema is
  /// `extra="forbid"` snake_case, so a camelCase payload is rejected as
  /// `schema_invalid` on every push. `target_date` is a DATE column.
  Map<String, dynamic> _payloadOf(Goal row) => {
        'id': row.id,
        'user_id': row.userId,
        'created_at': toRfc3339Millis(row.createdAt),
        'updated_at': toRfc3339Millis(row.updatedAt),
        'deleted_at':
            row.deletedAt == null ? null : toRfc3339Millis(row.deletedAt!),
        'server_version': row.serverVersion,
        'title': row.title,
        'description': row.description,
        'target_date':
            row.targetDate == null ? null : toWireDate(row.targetDate!),
        'progress_percent': row.progressPercent,
      };
}
