/// The write side a screen calls for task categories. See
/// `task_mutation_controller.dart` for the pattern this follows.
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kunim/core/db/app_database.dart';

import '../data/task_category_repository.dart';
import 'task_category_providers.dart';

class TaskCategoryMutationController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  TaskCategoryRepository get _repository =>
      ref.read(taskCategoryRepositoryProvider);

  Future<TaskCategory?> createCategory({
    required String name,
    String? color,
    int sortOrder = 0,
    String? userId,
  }) {
    return _run(() => _repository.createCategory(
          name: name,
          color: color,
          sortOrder: sortOrder,
          userId: userId,
        ));
  }

  Future<TaskCategory?> updateCategory(
    String id, {
    String? name,
    Value<String?> color = const Value.absent(),
  }) {
    return _run(() => _repository.updateCategory(id, name: name, color: color));
  }

  Future<void> deleteCategory(String id) => _runVoid(
        () => _repository.softDeleteCategory(id),
      );

  Future<void> reorderCategories(List<String> orderedIds) => _runVoid(
        () => _repository.reorderCategories(orderedIds),
      );

  Future<T?> _run<T>(Future<T> Function() action) async {
    state = const AsyncLoading();
    try {
      final result = await action();
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return null;
    }
  }

  Future<void> _runVoid(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

final taskCategoryMutationControllerProvider =
    AsyncNotifierProvider<TaskCategoryMutationController, void>(
  TaskCategoryMutationController.new,
);
