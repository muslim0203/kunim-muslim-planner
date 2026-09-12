/// Riverpod wiring for the goals feature — the only place under
/// `features/goals/` that touches `flutter_riverpod` or
/// `core/sync/sync_triggers.dart`. See `data/goal_repository.dart` and
/// `data/milestone_repository.dart` for the actual reads/writes, and
/// `domain/goal_progress.dart` / `domain/goal_with_milestones.dart` for
/// the pure values built on top of them.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_triggers.dart';
import '../data/goal_repository.dart';
import '../data/milestone_repository.dart';
import '../domain/goal_with_milestones.dart';

final goalRepositoryProvider = Provider<GoalRepository>((ref) {
  return GoalRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

final milestoneRepositoryProvider = Provider<MilestoneRepository>((ref) {
  return MilestoneRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

/// All non-deleted goals, for a goals-list screen.
final activeGoalsProvider = StreamProvider<List<Goal>>((ref) {
  return ref.watch(goalRepositoryProvider).watchActive();
});

final _goalByIdProvider = StreamProvider.family<Goal?, String>((ref, id) {
  return ref.watch(goalRepositoryProvider).watchById(id);
});

/// Live milestones for one goal, in display order.
final milestonesForGoalProvider =
    StreamProvider.family<List<Milestone>, String>((ref, goalId) {
  return ref.watch(milestoneRepositoryProvider).watchForGoal(goalId);
});

/// A goal-detail screen's data: the goal itself (nullable — see
/// [GoalWithMilestones]'s doc for why) plus its live milestones. Combines
/// two independent [StreamProvider]s reactively — a plain [Provider] that
/// watches both and re-derives its value whenever either changes — rather
/// than hand-rolling a stream merge.
final goalWithMilestonesProvider =
    Provider.family<AsyncValue<GoalWithMilestones>, String>((ref, goalId) {
  final goalAsync = ref.watch(_goalByIdProvider(goalId));
  final milestonesAsync = ref.watch(milestonesForGoalProvider(goalId));

  if (goalAsync.isLoading || milestonesAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (goalAsync.hasError) {
    return AsyncValue.error(goalAsync.error!, goalAsync.stackTrace!);
  }
  if (milestonesAsync.hasError) {
    return AsyncValue.error(
        milestonesAsync.error!, milestonesAsync.stackTrace!);
  }
  return AsyncValue.data(
    GoalWithMilestones(
      goal: goalAsync.value,
      milestones: milestonesAsync.value ?? const [],
    ),
  );
});

/// Mutation entry point for goal and milestone screens. [state] mirrors
/// the most recent mutation's outcome (`AsyncData(null)` idle/succeeded,
/// `AsyncLoading` in flight, `AsyncError` on failure) so a screen can
/// disable a button or show an inline error without its own try/catch —
/// the same pattern `core/sync/sync_engine.dart`'s `SyncStatusController`
/// uses for `SyncStatus`.
class GoalsController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  GoalRepository get _goals => ref.read(goalRepositoryProvider);
  MilestoneRepository get _milestones => ref.read(milestoneRepositoryProvider);

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(action);
  }

  Future<void> createGoal({
    required String title,
    String? description,
    DateTime? targetDate,
    int progressPercent = 0,
  }) {
    return _run(
      () => _goals.createGoal(
        title: title,
        description: description,
        targetDate: targetDate,
        progressPercent: progressPercent,
      ),
    );
  }

  Future<void> updateGoal({
    required String id,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? targetDate,
    bool clearTargetDate = false,
    int? progressPercent,
  }) {
    return _run(
      () => _goals.updateGoal(
        id: id,
        title: title,
        description: description,
        targetDate: targetDate,
        clearTargetDate: clearTargetDate,
        progressPercent: progressPercent,
      ),
    );
  }

  /// Convenience wrapper for the common "just change the progress number"
  /// action (e.g. a slider on the goal detail screen).
  Future<void> updateProgress(
      {required String id, required int progressPercent}) {
    return _run(
        () => _goals.updateProgress(id: id, progressPercent: progressPercent));
  }

  Future<void> deleteGoal(String id) {
    return _run(() => _goals.deleteGoal(id));
  }

  Future<void> addMilestone({
    required String goalId,
    required String title,
    DateTime? targetDate,
    int sortOrder = 0,
  }) {
    return _run(
      () => _milestones.createMilestone(
        goalId: goalId,
        title: title,
        targetDate: targetDate,
        sortOrder: sortOrder,
      ),
    );
  }

  Future<void> updateMilestone({
    required String id,
    String? title,
    DateTime? targetDate,
    bool clearTargetDate = false,
    int? sortOrder,
  }) {
    return _run(
      () => _milestones.updateMilestone(
        id: id,
        title: title,
        targetDate: targetDate,
        clearTargetDate: clearTargetDate,
        sortOrder: sortOrder,
      ),
    );
  }

  Future<void> completeMilestone(String id, {DateTime? completedAt}) {
    return _run(
        () => _milestones.completeMilestone(id: id, completedAt: completedAt));
  }

  Future<void> reopenMilestone(String id) {
    return _run(() => _milestones.reopenMilestone(id));
  }

  Future<void> deleteMilestone(String id) {
    return _run(() => _milestones.deleteMilestone(id));
  }
}

final goalsControllerProvider =
    NotifierProvider<GoalsController, AsyncValue<void>>(
  GoalsController.new,
);
