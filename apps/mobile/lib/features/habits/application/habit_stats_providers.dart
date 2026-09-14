/// Read-only habit streams for screens that aggregate across habits, such
/// as statistics. Kept in the application layer so other features never
/// import `habits/data/` directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import 'habit_repositories.dart';

/// Active (non-archived) habits, oldest first.
final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchActiveHabits();
});

/// Every live habit log across all habits, oldest first.
final allHabitLogsProvider = StreamProvider<List<HabitLog>>((ref) {
  return ref.watch(habitLogRepositoryProvider).watchAllLogs();
});
