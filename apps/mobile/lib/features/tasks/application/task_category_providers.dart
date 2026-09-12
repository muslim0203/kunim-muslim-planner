/// Riverpod wiring for the `task_categories` entity — mirrors
/// `task_providers.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';

import '../data/task_category_repository.dart';

final taskCategoryRepositoryProvider = Provider<TaskCategoryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TaskCategoryRepository(
    db,
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

/// All non-deleted categories, ordered by `sortOrder`.
final allTaskCategoriesProvider = StreamProvider<List<TaskCategory>>((ref) {
  return ref.watch(taskCategoryRepositoryProvider).watchAll();
});

final taskCategoryByIdProvider =
    StreamProvider.family<TaskCategory?, String>((ref, id) {
  return ref.watch(taskCategoryRepositoryProvider).watchById(id);
});
