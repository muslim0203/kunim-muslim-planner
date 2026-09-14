import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_triggers.dart';
import '../../habits/domain/local_day.dart';
import '../data/sleep_log_repository.dart';

final sleepLogRepositoryProvider = Provider<SleepLogRepository>((ref) {
  return SleepLogRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

final todaySleepLogProvider = StreamProvider<SleepLog?>((ref) {
  return ref.watch(sleepLogRepositoryProvider).watchForDay(LocalDay.now());
});

final recentSleepLogsProvider = StreamProvider<List<SleepLog>>((ref) {
  return ref.watch(sleepLogRepositoryProvider).watchRecent();
});
