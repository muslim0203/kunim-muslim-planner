/// Riverpod wiring for the two habits repositories. This is the only file
/// in the habits feature that constructs [HabitRepository]/
/// [HabitLogRepository] — every other provider/controller reads them from
/// here, never constructs its own.
///
/// This is also where `SyncTriggerScheduler.onLocalWrite()`
/// (`core/sync/sync_triggers.dart`) gets its first caller: each repository
/// is given a callback that reads `syncTriggerSchedulerProvider` and calls
/// it, satisfying the task's "after every successful local write, call
/// onLocalWrite()" requirement without either repository depending on
/// Riverpod directly (see `data/habit_local_write_hook.dart`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_triggers.dart';
import '../data/habit_log_repository.dart';
import '../data/habit_repository.dart';

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

final habitLogRepositoryProvider = Provider<HabitLogRepository>((ref) {
  return HabitLogRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});
