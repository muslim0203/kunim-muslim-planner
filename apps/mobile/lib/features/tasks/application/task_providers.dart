/// Riverpod wiring for the `tasks` entity: the repository provider (which
/// is where `SyncTriggerScheduler.onLocalWrite` actually gets wired in —
/// `core/sync/sync_triggers.dart` documents that no caller exists until a
/// feature repository provider does this) and the reactive read providers
/// a screen watches. No UI strings, no widgets — see
/// `task_mutation_controller.dart` for the write side.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';

import '../data/task_repository.dart';
import '../domain/task_ordering.dart';

/// The single [TaskRepository] instance for the app session. This is the
/// ONLY place `SyncTriggerScheduler.onLocalWrite` is wired to a real
/// caller — every `TaskRepository` mutation calls it internally.
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TaskRepository(
    db,
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

/// All non-deleted tasks, reactive (Drift `watch()` under the hood).
final allTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAll();
});

/// Today's tasks (due today or overdue), pre-sorted by
/// `domain/task_ordering.dart#compareForTodayList`. Derived from
/// [allTasksProvider] rather than a separate SQL query so it stays
/// reactive to every task write without duplicating the "non-deleted"
/// filter.
final todayTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref
      .watch(taskRepositoryProvider)
      .watchAll()
      .map((tasks) => todayTasksFrom(tasks));
});

/// Non-deleted tasks filed under one category. A dangling `categoryId`
/// (the category was deleted, or has not synced yet) is not filtered out
/// here — see `task_repository.dart#watchByCategory`.
final tasksByCategoryProvider =
    StreamProvider.family<List<Task>, String>((ref, categoryId) {
  return ref.watch(taskRepositoryProvider).watchByCategory(categoryId);
});

/// A single task by id, or `null` if it does not exist. Emits again
/// whenever that row changes, including a soft delete (the row still
/// emits with `deletedAt` set, per `watchById`'s doc comment).
final taskByIdProvider = StreamProvider.family<Task?, String>((ref, id) {
  return ref.watch(taskRepositoryProvider).watchById(id);
});
