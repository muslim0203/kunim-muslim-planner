import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_triggers.dart';
import '../../habits/domain/local_day.dart';
import '../data/family_log_repository.dart';

final familyLogRepositoryProvider = Provider<FamilyLogRepository>((ref) {
  return FamilyLogRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

final todayFamilyLogProvider = StreamProvider<FamilyLog?>((ref) {
  return ref.watch(familyLogRepositoryProvider).watchForDay(LocalDay.now());
});

final recentFamilyLogsProvider = StreamProvider<List<FamilyLog>>((ref) {
  return ref.watch(familyLogRepositoryProvider).watchRecent();
});
