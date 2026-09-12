/// The write side a screen calls for the manual Top-3 pin list. Unlike
/// `TaskMutationController`/`TaskCategoryMutationController`, this does
/// NOT go through `writeWithOutbox` — see `data/task_top_three_store.dart`
/// for why the pin list is local-only and never touches the sync outbox.
/// Consequently it also never calls `SyncTriggerScheduler.onLocalWrite`:
/// that trigger exists to flush the outbox, and a pin/unpin never adds an
/// outbox entry.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/task_top_three_store.dart';
import 'top_three_providers.dart';

class TopThreeMutationController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  TaskTopThreeStore get _store => ref.read(taskTopThreeStoreProvider);

  Future<void> pin(String taskId) => _run(() => _store.pin(taskId));

  Future<void> unpin(String taskId) => _run(() => _store.unpin(taskId));

  Future<void> replace(List<String> orderedTaskIds) =>
      _run(() => _store.replace(orderedTaskIds));

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

final topThreeMutationControllerProvider =
    AsyncNotifierProvider<TopThreeMutationController, void>(
  TopThreeMutationController.new,
);
