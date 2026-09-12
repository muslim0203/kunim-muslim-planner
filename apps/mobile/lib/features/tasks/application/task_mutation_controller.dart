/// The write side a screen calls for tasks: wraps `TaskRepository` in
/// `AsyncValue` loading/error state (via `AsyncNotifier`, Riverpod 3 —
/// there is no `StateProvider`) so a screen can show a spinner/snackbar
/// without repeating try/catch boilerplate. `TaskRepository` itself
/// remains the single source of truth for what each mutation actually
/// does (outbox write + `onLocalWrite`); this controller adds no
/// business logic of its own.
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/db/tables/tasks_table.dart' show TaskPriority;

import '../data/task_repository.dart';
import 'task_providers.dart';

class TaskMutationController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  TaskRepository get _repository => ref.read(taskRepositoryProvider);

  Future<Task?> createTask({
    required String title,
    String? description,
    String? categoryId,
    TaskPriority priority = TaskPriority.medium,
    DateTime? dueDate,
    String? userId,
  }) {
    return _run(() => _repository.createTask(
          title: title,
          description: description,
          categoryId: categoryId,
          priority: priority,
          dueDate: dueDate,
          userId: userId,
        ));
  }

  Future<Task?> updateTask(
    String id, {
    String? title,
    Value<String?> description = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    TaskPriority? priority,
    Value<DateTime?> dueDate = const Value.absent(),
  }) {
    return _run(() => _repository.updateTask(
          id,
          title: title,
          description: description,
          categoryId: categoryId,
          priority: priority,
          dueDate: dueDate,
        ));
  }

  /// See `domain/task_status.dart` / `TaskRepository.setCompleted` for the
  /// ADR-0002 rule 8 (`max_wins` `completed_at`, no synced `completed`
  /// flag) caveat that also applies here.
  Future<Task?> completeTask(String id) =>
      _run(() => _repository.completeTask(id));

  Future<Task?> uncompleteTask(String id) =>
      _run(() => _repository.uncompleteTask(id));

  Future<void> deleteTask(String id) => _runVoid(
        () => _repository.softDeleteTask(id),
      );

  /// Runs [action], tracking loading/error in [state]; returns the
  /// action's result on success or `null` on failure (the error itself is
  /// left in [state] for the screen to read/display).
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

  /// Same as [_run] but for actions with no meaningful return value
  /// (avoids instantiating [_run]'s generic with `void`).
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

final taskMutationControllerProvider =
    AsyncNotifierProvider<TaskMutationController, void>(
  TaskMutationController.new,
);
