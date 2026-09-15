/// Riverpod wiring for prayer marks.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_triggers.dart';
import '../../habits/domain/local_day.dart';
import '../data/prayer_log_repository.dart';
import '../domain/prayer_log_status.dart';

final prayerLogRepositoryProvider = Provider<PrayerLogRepository>((ref) {
  return PrayerLogRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

/// The marks of one local day, keyed by prayer key. The family key is the
/// day's UTC-midnight tag (`LocalDay.toUtcMidnight`).
final prayerMarksProvider =
    StreamProvider.family<Map<String, PrayerLogStatus>, DateTime>((ref, tag) {
  return ref
      .watch(prayerLogRepositoryProvider)
      .watchDay(LocalDay.fromUtcMidnight(tag));
});

/// Marks from the last two weeks, oldest first; enough for the week in
/// statistics.
final recentPrayerLogsProvider = StreamProvider<List<PrayerLog>>((ref) {
  return ref
      .watch(prayerLogRepositoryProvider)
      .watchSince(LocalDay.now().addDays(-13));
});
