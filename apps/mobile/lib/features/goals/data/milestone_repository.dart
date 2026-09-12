/// Data-layer access to the `milestones` table (ADR-0002 §1 /
/// `docs/sync-conflict-matrix.md` rule 18 — same LWW + soft-delete rule as
/// `goals`). See `goal_repository.dart`'s class doc for the
/// `writeWithOutbox` + `onLocalWrite` pattern shared by both.
///
/// [Milestone.goalId] is a loose reference with no SQL foreign key
/// (`goals_table.dart`'s class doc): a milestone can legitimately exist
/// locally before its parent goal has synced from another device. Every
/// query method here is written against the `milestones` table alone
/// (never an inner join against `goals`), so a dangling/not-yet-synced
/// `goalId` never causes a milestone to be dropped from a result or a
/// query to throw.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';

const _uuid = Uuid();

class MilestoneRepository extends SyncableRepository {
  MilestoneRepository(
    super.db, {
    this.onLocalWrite,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final void Function()? onLocalWrite;
  final DateTime Function() _now;

  /// All non-deleted milestones for [goalId], in display order. Returns
  /// an empty stream value (never throws) when [goalId] does not match
  /// any local goal — see the class doc.
  Stream<List<Milestone>> watchForGoal(String goalId) {
    final query = db.select(db.milestones)
      ..where((m) => m.goalId.equals(goalId) & m.deletedAt.isNull())
      ..orderBy([
        (m) => OrderingTerm(expression: m.sortOrder),
        (m) => OrderingTerm(expression: m.createdAt),
      ]);
    return query.watch();
  }

  Future<Milestone> createMilestone({
    required String goalId,
    required String title,
    DateTime? targetDate,
    int sortOrder = 0,
    String? userId,
  }) {
    final now = _now();
    final row = Milestone(
      id: _uuid.v4(),
      userId: userId,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      serverVersion: 0,
      dirty: true,
      goalId: goalId,
      title: title,
      targetDate: targetDate,
      completedAt: null,
      sortOrder: sortOrder,
    );
    return _persist(row);
  }

  /// Updates fields of an existing milestone. `null` for [title]/
  /// [sortOrder] means "leave unchanged"; [targetDate]/[clearTargetDate]
  /// follow the same "leave unchanged vs. explicitly clear" convention as
  /// `GoalRepository.updateGoal`. Throws [StateError] if [id] does not
  /// exist locally.
  Future<Milestone> updateMilestone({
    required String id,
    String? title,
    DateTime? targetDate,
    bool clearTargetDate = false,
    int? sortOrder,
  }) async {
    final existing = await _require(id);
    final updated = existing.copyWith(
      title: title,
      targetDate: clearTargetDate
          ? const Value(null)
          : (targetDate == null ? const Value.absent() : Value(targetDate)),
      sortOrder: sortOrder,
      updatedAt: _now(),
    );
    return _persist(updated);
  }

  /// Marks a milestone done. [completedAt] defaults to now; pass it
  /// explicitly to backdate.
  Future<Milestone> completeMilestone(
      {required String id, DateTime? completedAt}) async {
    final existing = await _require(id);
    final now = _now();
    final updated = existing.copyWith(
        completedAt: Value(completedAt ?? now), updatedAt: now);
    return _persist(updated);
  }

  /// Reverses [completeMilestone] — clears `completed_at`.
  Future<Milestone> reopenMilestone(String id) async {
    final existing = await _require(id);
    final updated =
        existing.copyWith(completedAt: const Value(null), updatedAt: _now());
    return _persist(updated);
  }

  /// Soft-deletes a milestone. A no-op if it is already deleted or does
  /// not exist locally.
  Future<void> deleteMilestone(String id) async {
    final existing = await (db.select(db.milestones)
          ..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    if (existing == null || existing.deletedAt != null) return;

    final now = _now();
    final updated = existing.copyWith(deletedAt: Value(now), updatedAt: now);
    await writeWithOutbox<void>(
      entity: 'milestones',
      rowId: id,
      op: SyncOp.delete,
      payload: syncPayload(updated.toJson()),
      write: () => db.update(db.milestones).replace(updated),
    );
    onLocalWrite?.call();
  }

  Future<Milestone> _require(String id) async {
    final existing = await (db.select(db.milestones)
          ..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      throw StateError('Milestone not found: $id');
    }
    return existing;
  }

  Future<Milestone> _persist(Milestone row) async {
    final result = await writeWithOutbox<Milestone>(
      entity: 'milestones',
      rowId: row.id,
      op: SyncOp.upsert,
      payload: syncPayload(row.toJson()),
      write: () async {
        await db.into(db.milestones).insertOnConflictUpdate(row);
        return row;
      },
    );
    onLocalWrite?.call();
    return result;
  }
}
