/// Which part of a life is slipping, read from what the app actually
/// recorded.
///
/// Rules, not a model, and deliberately only as clever as the data allows:
/// every number here comes from days the user planned something and days they
/// did it. Nothing is inferred about a day nobody planned — an empty day is
/// not a failed one — and nothing is said that the user could not check
/// against their own grid.
///
/// The vocabulary is the one they answered at sign-up ([FocusArea]), so what
/// the app tells them later is in the same words as what they asked for.
library;

import '../../onboarding/domain/onboarding_answers.dart';

/// How an area is doing over the window.
enum AreaState {
  /// Nearly always done.
  strong,

  /// Done more often than not.
  steady,

  /// Missed more often than done.
  slipping,

  /// Nothing was planned here at all — not a failure, an absence.
  untouched,
}

/// The one thing worth changing. Each maps to a single tap in the UI, because
/// advice nobody can act on in one step is advice nobody takes.
enum AreaAdvice {
  /// It is working; leave it alone.
  keepGoing,

  /// The daily amount was never once reached: it is too big, not the user.
  lowerTarget,

  /// It gets done some days and not others — usually the hour, not the will.
  moveTime,

  /// It was going and stopped.
  startAgain,

  /// There is nothing here to measure yet.
  addWidget,
}

/// One widget's (or the prayers') record over the window.
class AreaObservation {
  const AreaObservation({
    required this.area,
    required this.title,
    required this.days,
    this.habitId,
    this.reminderMinutes,
    this.everMetTarget = true,
  });

  final FocusArea area;
  final String title;

  /// Oldest day first, ending with today. `null` means nothing was planned
  /// that day, which is never counted as a miss.
  final List<bool?> days;

  /// The widget this came from, so the UI can open it. Null for the prayers,
  /// which have their own screen.
  final String? habitId;
  final int? reminderMinutes;

  /// Whether the day's amount was ever reached. False says the target is too
  /// big far more often than it says the user is unwilling.
  final bool everMetTarget;
}

class AreaInsight {
  const AreaInsight({
    required this.area,
    required this.title,
    required this.plannedDays,
    required this.doneDays,
    required this.trend,
    required this.state,
    required this.advice,
    this.habitId,
  });

  final FocusArea area;

  /// The widget this is mostly about — the weakest one, when an area has
  /// several.
  final String title;
  final String? habitId;

  final int plannedDays;
  final int doneDays;

  /// Share of planned days that were done, 0..100. Zero when nothing was
  /// planned, which [state] reports as [AreaState.untouched] rather than as
  /// a failure.
  int get donePercent =>
      plannedDays == 0 ? 0 : ((doneDays / plannedDays) * 100).round();

  /// Last week's share minus the week before's, in points. Negative means it
  /// is getting worse.
  final int trend;

  final AreaState state;
  final AreaAdvice advice;
}

abstract final class AreaAnalysis {
  /// "Recently" is the last week; the week before it is what recently is
  /// compared against.
  static const int recentDays = 7;

  /// Done nearly every planned day.
  static const int strongPercent = 80;

  /// Done more often than missed.
  static const int steadyPercent = 50;

  /// A fall this big is the difference between a habit and a memory.
  static const int fallingPoints = 20;

  /// The areas worth saying something about, weakest first.
  ///
  /// [wanted] are the areas the user said they want to strengthen: one of
  /// those with nothing to measure is reported as [AreaState.untouched]
  /// rather than left out, because "you asked for this and there is nothing
  /// here" is the most useful thing the app can say.
  static List<AreaInsight> compute({
    required List<AreaObservation> observations,
    List<FocusArea> wanted = const [],
  }) {
    final byArea = <FocusArea, List<AreaObservation>>{};
    for (final observation in observations) {
      (byArea[observation.area] ??= []).add(observation);
    }
    for (final area in wanted) {
      byArea.putIfAbsent(area, () => const []);
    }

    final insights = [
      for (final entry in byArea.entries) _insightFor(entry.key, entry.value),
    ];

    insights.sort((a, b) {
      final byState = _severity(a.state).compareTo(_severity(b.state));
      if (byState != 0) return byState;
      final byPercent = a.donePercent.compareTo(b.donePercent);
      if (byPercent != 0) return byPercent;
      return a.trend.compareTo(b.trend);
    });
    return insights;
  }

  static int _severity(AreaState state) {
    return switch (state) {
      AreaState.slipping => 0,
      AreaState.untouched => 1,
      AreaState.steady => 2,
      AreaState.strong => 3,
    };
  }

  static AreaInsight _insightFor(
    FocusArea area,
    List<AreaObservation> observations,
  ) {
    var planned = 0;
    var done = 0;
    var recentPlanned = 0;
    var recentDone = 0;
    var earlierPlanned = 0;
    var earlierDone = 0;

    for (final observation in observations) {
      final days = observation.days;
      for (var i = 0; i < days.length; i++) {
        final outcome = days[i];
        if (outcome == null) continue;
        planned++;
        if (outcome) done++;

        final fromEnd = days.length - 1 - i;
        if (fromEnd < recentDays) {
          recentPlanned++;
          if (outcome) recentDone++;
        } else if (fromEnd < recentDays * 2) {
          earlierPlanned++;
          if (outcome) earlierDone++;
        }
      }
    }

    final weakest = _weakest(observations);
    final percent = planned == 0 ? 0 : ((done / planned) * 100).round();
    final trend = (recentPlanned == 0 || earlierPlanned == 0)
        ? 0
        : ((recentDone / recentPlanned) * 100).round() -
            ((earlierDone / earlierPlanned) * 100).round();

    final state = planned == 0
        ? AreaState.untouched
        : percent >= strongPercent
            ? AreaState.strong
            : percent >= steadyPercent
                ? AreaState.steady
                : AreaState.slipping;

    return AreaInsight(
      area: area,
      title: weakest?.title ?? '',
      habitId: weakest?.habitId,
      plannedDays: planned,
      doneDays: done,
      trend: trend,
      state: state,
      advice: _adviceFor(state: state, trend: trend, weakest: weakest),
    );
  }

  /// The widget the area's trouble is really about: the one missed most.
  static AreaObservation? _weakest(List<AreaObservation> observations) {
    AreaObservation? worst;
    var worstShare = 2.0;
    for (final observation in observations) {
      final planned = observation.days.whereType<bool>().length;
      if (planned == 0) {
        worst ??= observation;
        continue;
      }
      final share =
          observation.days.where((done) => done == true).length / planned;
      if (share < worstShare) {
        worstShare = share;
        worst = observation;
      }
    }
    return worst;
  }

  static AreaAdvice _adviceFor({
    required AreaState state,
    required int trend,
    required AreaObservation? weakest,
  }) {
    return switch (state) {
      AreaState.untouched => AreaAdvice.addWidget,
      AreaState.strong => AreaAdvice.keepGoing,
      // Holding up, but falling fast enough to be worth a nudge.
      AreaState.steady =>
        trend <= -fallingPoints ? AreaAdvice.moveTime : AreaAdvice.keepGoing,
      AreaState.slipping => _slippingAdvice(trend, weakest),
    };
  }

  static AreaAdvice _slippingAdvice(int trend, AreaObservation? weakest) {
    // Never once reached means the amount is wrong, not the person.
    if (weakest != null && !weakest.everMetTarget) {
      return AreaAdvice.lowerTarget;
    }
    // It has an hour and that hour is not working.
    if (weakest?.reminderMinutes != null && trend < 0) {
      return AreaAdvice.moveTime;
    }
    return AreaAdvice.startAgain;
  }
}
