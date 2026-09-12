/// Riverpod wiring for the manual Top-3 selection
/// (`domain/top_three_selection.dart`). Local-only, not written through
/// the outbox — see `data/task_top_three_store.dart` for why.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kunim/core/db/app_database.dart';

import '../data/task_top_three_store.dart';
import '../domain/top_three_selection.dart';
import 'task_providers.dart';

final taskTopThreeStoreProvider = Provider<TaskTopThreeStore>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TaskTopThreeStore(db);
});

/// The raw pinned-id selection, reactive.
final topThreeSelectionProvider = StreamProvider<TopThreeSelection>((ref) {
  return ref.watch(taskTopThreeStoreProvider).watch();
});

/// The pinned selection resolved to actual [Task] rows, in pin order. A
/// pin whose task was soft-deleted or does not exist (dangling pin — the
/// same tolerance principle as a dangling `categoryId`) is silently
/// dropped rather than surfaced as an error; a screen showing this list
/// never crashes on a stale pin.
final topThreeTasksProvider = Provider<AsyncValue<List<Task>>>((ref) {
  final selectionAsync = ref.watch(topThreeSelectionProvider);
  final tasksAsync = ref.watch(allTasksProvider);

  return selectionAsync.when(
    data: (selection) => tasksAsync.whenData((tasks) {
      final byId = {for (final task in tasks) task.id: task};
      return selection.taskIds.map((id) => byId[id]).whereType<Task>().toList();
    }),
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});
