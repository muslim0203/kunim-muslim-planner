/// The single write entry point for the habits feature's screens: every
/// create/update/archive/log mutation goes through this controller, which
/// delegates to the two repositories and exposes only their typed
/// `AsyncValue<void>` outcome — no UI strings, no raw Drift/outbox details
/// leak past this layer.
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/habit_log_repository.dart';
import '../data/habit_repository.dart';
import '../domain/habit_kind.dart';
import '../domain/habit_schedule.dart';
import '../domain/local_day.dart';
import 'habit_repositories.dart';

/// `state` reflects the most recently invoked method's outcome:
/// [AsyncLoading] while it runs, [AsyncData] (`null`) on success,
/// [AsyncError] if the repository call threw. There is no other state to
/// read — this controller does not cache habit data itself (the `*_provider`
/// StreamProviders in this same directory own reads).
class HabitMutationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Idle: nothing to do until a mutation method is called.
  }

  HabitRepository get _habits => ref.read(habitRepositoryProvider);
  HabitLogRepository get _logs => ref.read(habitLogRepositoryProvider);

  Future<void> createHabit({
    String? userId,
    required String title,
    String? description,
    HabitSchedule schedule = HabitSchedule.defaultSchedule,
    int targetCount = 1,
    String? color,
    HabitKind kind = HabitKind.custom,
    int? totalTarget,
  }) {
    return _run(
      () => _habits.createHabit(
        userId: userId,
        title: title,
        description: description,
        schedule: schedule,
        targetCount: targetCount,
        color: color,
        kind: kind,
        totalTarget: totalTarget,
      ),
    );
  }

  Future<void> updateHabit({
    required String id,
    String? title,
    String? Function()? description,
    HabitSchedule? schedule,
    int? targetCount,
    String? Function()? color,
    HabitKind? kind,
    int? Function()? totalTarget,
  }) {
    return _run(
      () => _habits.updateHabit(
        id: id,
        title: title == null ? const Value.absent() : Value(title),
        description:
            description == null ? const Value.absent() : Value(description()),
        schedule: schedule == null ? const Value.absent() : Value(schedule),
        targetCount:
            targetCount == null ? const Value.absent() : Value(targetCount),
        color: color == null ? const Value.absent() : Value(color()),
        kind: kind == null ? const Value.absent() : Value(kind),
        totalTarget:
            totalTarget == null ? const Value.absent() : Value(totalTarget()),
      ),
    );
  }

  Future<void> archiveHabit(String id) {
    return _run(() => _habits.archiveHabit(id));
  }

  Future<void> logCompletion({
    required String habitId,
    required LocalDay day,
    String? userId,
  }) {
    return _run(
      () => _logs.logCompletion(habitId: habitId, day: day, userId: userId),
    );
  }

  Future<void> adjustCount({
    required String habitId,
    required LocalDay day,
    String? userId,
    int delta = 1,
  }) {
    return _run(
      () => _logs.adjustCount(
        habitId: habitId,
        day: day,
        userId: userId,
        delta: delta,
      ),
    );
  }

  Future<void> adjustValue({
    required String habitId,
    required LocalDay day,
    String? userId,
    required double delta,
  }) {
    return _run(
      () => _logs.adjustValue(
        habitId: habitId,
        day: day,
        userId: userId,
        delta: delta,
      ),
    );
  }

  Future<void> setNote({
    required String habitId,
    required LocalDay day,
    String? userId,
    String? note,
  }) {
    return _run(
      () =>
          _logs.setNote(habitId: habitId, day: day, userId: userId, note: note),
    );
  }

  Future<void> removeLog({
    required String habitId,
    required LocalDay day,
    String? userId,
  }) {
    return _run(
      () => _logs.removeLog(habitId: habitId, day: day, userId: userId),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(action);
  }
}

final habitMutationControllerProvider =
    AsyncNotifierProvider<HabitMutationController, void>(
  HabitMutationController.new,
);
