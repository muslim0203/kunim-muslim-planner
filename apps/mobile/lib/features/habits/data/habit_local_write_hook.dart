/// Shared plumbing for the two habits repositories: every mutation must go
/// through `writeWithOutbox` (`core/db/base_repository.dart`) AND, on
/// success only, call `SyncTriggerScheduler.onLocalWrite()`
/// (`core/sync/sync_triggers.dart`) — that scheduler currently has no
/// caller anywhere in the app; wiring it up here (and from
/// `application/habit_providers.dart`) is what gives it one.
///
/// This file does not import Riverpod: [onLocalWrite] is a plain callback
/// injected by whoever constructs the repository, so the repositories
/// themselves stay unit-testable with a bare in-memory `AppDatabase` and a
/// spy callback, with no Riverpod container involved (see
/// `test/features/habits/data/*`). The application layer is what supplies
/// the real callback bound to `syncTriggerSchedulerProvider`.
library;

import '../../../core/db/base_repository.dart';

/// Mixes into a [SyncableRepository] subclass to get [writeAndNotify]: the
/// same contract as [SyncableRepository.writeWithOutbox], plus calling
/// [onLocalWrite] exactly once after it succeeds, and never when it
/// throws.
mixin HabitLocalWriteHook on SyncableRepository {
  /// Called once per successful mutation. Bound to
  /// `ref.read(syncTriggerSchedulerProvider).onLocalWrite` in production;
  /// a test passes a spy.
  void Function() get onLocalWrite;

  Future<T> writeAndNotify<T>({
    required String entity,
    required String rowId,
    required SyncOp op,
    required Map<String, dynamic> payload,
    required Future<T> Function() write,
  }) async {
    final result = await writeWithOutbox<T>(
      entity: entity,
      rowId: rowId,
      op: op,
      payload: payload,
      write: write,
    );
    // Unreached if writeWithOutbox threw — its transaction (and this line)
    // never completes, so a failed write can never trigger a sync cycle.
    onLocalWrite();
    return result;
  }
}
