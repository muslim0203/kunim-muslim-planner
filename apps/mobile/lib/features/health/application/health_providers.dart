import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_triggers.dart';
import '../../habits/domain/local_day.dart';
import '../data/health_log_repository.dart';

final healthLogRepositoryProvider = Provider<HealthLogRepository>((ref) {
  return HealthLogRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

final todayHealthLogProvider = StreamProvider<HealthLog?>((ref) {
  return ref.watch(healthLogRepositoryProvider).watchForDay(LocalDay.now());
});

final recentHealthLogsProvider = StreamProvider<List<HealthLog>>((ref) {
  return ref.watch(healthLogRepositoryProvider).watchRecent();
});
