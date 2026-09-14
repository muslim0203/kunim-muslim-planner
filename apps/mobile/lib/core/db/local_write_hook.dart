/// [LocalWriteHook]: `writeWithOutbox` plus "tell the sync scheduler",
/// shared by feature repositories that sync.
///
/// The same contract as `HabitLocalWriteHook` (`features/habits/data`),
/// lifted into `core/` so new features do not depend on the habits feature.
/// The callback is injected by the application layer
/// (`ref.read(syncTriggerSchedulerProvider).onLocalWrite`), which keeps the
/// repositories testable with a bare in-memory database and a spy.
library;

import 'base_repository.dart';

mixin LocalWriteHook on SyncableRepository {
  /// Called once per successful mutation, never when the write throws.
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
    onLocalWrite();
    return result;
  }
}
