/// A single habit's full log history, newest first.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import 'habit_repositories.dart';

final habitLogHistoryProvider = StreamProvider.family<List<HabitLog>, String>((
  ref,
  habitId,
) {
  final repo = ref.watch(habitLogRepositoryProvider);
  return repo.watchLogsForHabit(habitId);
});
