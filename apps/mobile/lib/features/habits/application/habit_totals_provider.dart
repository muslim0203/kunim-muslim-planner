/// Everything logged per habit, for the widgets that work towards a total.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import 'habit_stats_providers.dart';

/// Sum of every live log's `count`, keyed by habit id. Empty while the logs
/// are still loading, so a widget shows 0 rather than a spinner.
final habitTotalsProvider = Provider<Map<String, int>>((ref) {
  final logs = ref.watch(allHabitLogsProvider).value ?? const <HabitLog>[];
  final totals = <String, int>{};
  for (final log in logs) {
    totals.update(
      log.habitId,
      (sum) => sum + log.count,
      ifAbsent: () => log.count,
    );
  }
  return totals;
});
