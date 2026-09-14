import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_triggers.dart';
import '../../habits/domain/local_day.dart';
import '../data/mood_log_repository.dart';

final moodLogRepositoryProvider = Provider<MoodLogRepository>((ref) {
  return MoodLogRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

final todayMoodLogProvider = StreamProvider<MoodLog?>((ref) {
  return ref.watch(moodLogRepositoryProvider).watchForDay(LocalDay.now());
});

final recentMoodLogsProvider = StreamProvider<List<MoodLog>>((ref) {
  return ref.watch(moodLogRepositoryProvider).watchRecent();
});
