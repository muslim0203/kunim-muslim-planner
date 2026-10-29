/// Turns the onboarding answers into a day the user can actually keep.
///
/// Rules, not a model: the same answers always give the same plan, it works
/// with no connection and costs nothing to run, and every suggestion can be
/// explained in one line ([SuggestionReason]). A language model can write
/// nicer prose about this later; it cannot make the arithmetic of a day any
/// different.
///
/// Two things decide what comes out:
/// - **What was said.** A weak area outranks an interest, because "my
///   reading has slipped" and "I like reading" are different statements, and
///   an interest outranks what the occupation implies, which is only a guess.
/// - **What the day holds.** Every suggestion costs minutes, and the user
///   said how many they have. A plan that overruns the budget is the one
///   abandoned in the first week, so targets are scaled down to fit and the
///   suggestions that still do not fit are left out rather than squeezed in.
library;

import '../../habits/domain/habit_kind.dart';
import 'onboarding_answers.dart';

/// Why a widget is being suggested. The UI turns this into one short line;
/// a suggestion nobody can explain is one nobody keeps.
enum SuggestionReason {
  /// The user named this area as the one they want to strengthen.
  focusArea,

  /// The user named it as an interest.
  interest,

  /// Nobody named it: it follows from what the user does all day.
  occupation,
}

class WidgetSuggestion {
  const WidgetSuggestion({
    required this.kind,
    required this.dailyTarget,
    required this.reason,
    required this.estimatedMinutes,
    this.reminderMinutes,
  });

  final HabitKind kind;

  /// In the kind's own unit — pages, ayahs, minutes, repetitions, glasses.
  final int dailyTarget;
  final SuggestionReason reason;

  /// What this costs out of the day's budget.
  final int estimatedMinutes;

  /// Minutes from local midnight, or null for something that has no hour of
  /// its own (drinking water is all day long).
  final int? reminderMinutes;

  WidgetSuggestion copyWith({int? dailyTarget, int? estimatedMinutes}) {
    return WidgetSuggestion(
      kind: kind,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      reason: reason,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      reminderMinutes: reminderMinutes,
    );
  }
}

abstract final class SuggestionEngine {
  /// A home screen holds this many widgets before it stops being a glance.
  static const int maxSuggestions = 6;

  /// The plan for [answers], best first. Empty when nothing was answered:
  /// the app does not guess a life from a blank form.
  static List<WidgetSuggestion> suggest(OnboardingAnswers answers) {
    if (answers.isEmpty) return const [];

    // Built in order rather than sorted afterwards: the order the user
    // answered in is itself an answer, and a sort by anything else (enum
    // order, a name) would quietly replace it with an arbitrary one.
    final ordered = <MapEntry<HabitKind, SuggestionReason>>[];
    final seen = <HabitKind>{};
    void add(HabitKind kind, SuggestionReason reason) {
      // A kind already here was put there by a stronger statement.
      if (seen.add(kind)) ordered.add(MapEntry(kind, reason));
    }

    for (final area in answers.focusAreas) {
      for (final kind in _kindsOfArea(area)) {
        add(kind, SuggestionReason.focusArea);
      }
    }
    for (final interest in answers.interests) {
      add(kindOfInterest(interest), SuggestionReason.interest);
    }
    for (final kind in _kindsOfOccupation(answers.occupation)) {
      add(kind, SuggestionReason.occupation);
    }

    return _fitToBudget(ordered, answers.budget);
  }

  /// Spends the day's minutes in two passes.
  ///
  /// Everything the user actually said — a weak area, an interest — gets its
  /// smallest honest version first; only then does what is left grow those
  /// targets towards their defaults, and only after that does a guess from
  /// the occupation get any room at all. One pass, strongest first, would
  /// let a single 30-minute suggestion swallow a 30-minute day and drop the
  /// interest the user named two screens earlier — which is exactly the plan
  /// nobody keeps.
  static List<WidgetSuggestion> _fitToBudget(
    List<MapEntry<HabitKind, SuggestionReason>> ordered,
    int budget,
  ) {
    final stated = [
      for (final entry in ordered)
        if (entry.value != SuggestionReason.occupation) entry,
    ];
    final implied = [
      for (final entry in ordered)
        if (entry.value == SuggestionReason.occupation) entry,
    ];

    final plan = <WidgetSuggestion>[];
    var spent = 0;

    // Pass one: the smallest version of everything the user named.
    for (final entry in stated) {
      if (plan.length >= maxSuggestions) break;
      final smallest = _smallestTarget(entry.key);
      if (smallest == null) continue;
      final cost = minutesFor(entry.key, smallest);
      if (cost > 0 && spent + cost > budget) continue;
      plan.add(_suggestion(entry.key, smallest, entry.value, cost));
      spent += cost;
    }

    // Pass two: grow them, in the same order, towards what the kind asks for.
    for (var i = 0; i < plan.length; i++) {
      final current = plan[i];
      final wanted = current.kind.dailyTarget;
      if (current.dailyTarget >= wanted) continue;
      final room = budget - spent + current.estimatedMinutes;
      if (room <= current.estimatedMinutes) continue;
      final target = _targetForMinutes(current.kind, room);
      if (target == null || target <= current.dailyTarget) continue;
      final cost = minutesFor(current.kind, target);
      spent += cost - current.estimatedMinutes;
      plan[i] = current.copyWith(dailyTarget: target, estimatedMinutes: cost);
    }

    // Pass three: what the occupation implies, with whatever is left.
    for (final entry in implied) {
      if (plan.length >= maxSuggestions) break;
      final kind = entry.key;
      final cost = minutesFor(kind, kind.dailyTarget);
      if (cost == 0) {
        plan.add(_suggestion(kind, kind.dailyTarget, entry.value, 0));
        continue;
      }
      final left = budget - spent;
      if (left <= 0) continue;
      if (cost <= left) {
        plan.add(_suggestion(kind, kind.dailyTarget, entry.value, cost));
        spent += cost;
        continue;
      }
      final smaller = _targetForMinutes(kind, left);
      if (smaller == null) continue;
      final smallerCost = minutesFor(kind, smaller);
      plan.add(_suggestion(kind, smaller, entry.value, smallerCost));
      spent += smallerCost;
    }

    return plan;
  }

  static WidgetSuggestion _suggestion(
    HabitKind kind,
    int target,
    SuggestionReason reason,
    int minutes,
  ) {
    return WidgetSuggestion(
      kind: kind,
      dailyTarget: target,
      reason: reason,
      estimatedMinutes: minutes,
      reminderMinutes: defaultTimeOf(kind),
    );
  }

  /// What a target costs in minutes. Rough on purpose — the point is to keep
  /// a plan inside a real day, not to time anyone.
  static int minutesFor(HabitKind kind, int target) {
    return switch (kind) {
      HabitKind.book => target * 2, // a page of a book, read properly
      HabitKind.quran => target, // an ayah, read with its meaning
      HabitKind.study ||
      HabitKind.sport ||
      HabitKind.running ||
      HabitKind.walk ||
      HabitKind.language ||
      HabitKind.family =>
        target,
      HabitKind.zikr => (target / 33).ceil(),
      HabitKind.mood || HabitKind.journal => 2,
      HabitKind.dua => 3,
      HabitKind.charity => 5,
      // Drinking water, eating well, fasting, going to bed and getting up
      // on time take no slice of the day of their own.
      HabitKind.water ||
      HabitKind.diet ||
      HabitKind.fasting ||
      HabitKind.sleep ||
      HabitKind.earlyRise =>
        0,
      HabitKind.custom => target,
    };
  }

  /// The smallest target of [kind] still worth doing, or null when even that
  /// does not fit in [minutes].
  static int? _targetForMinutes(HabitKind kind, int minutes) {
    final smallest = _smallestTarget(kind);
    if (smallest == null) return null;
    if (minutesFor(kind, smallest) > minutes) return null;

    return switch (kind) {
      HabitKind.book => (minutes ~/ 2).clamp(smallest, kind.dailyTarget),
      HabitKind.zikr => ((minutes * 33) ~/ 1).clamp(smallest, kind.dailyTarget),
      HabitKind.quran ||
      HabitKind.study ||
      HabitKind.sport ||
      HabitKind.running ||
      HabitKind.walk ||
      HabitKind.language ||
      HabitKind.family ||
      HabitKind.custom =>
        minutes.clamp(smallest, kind.dailyTarget),
      HabitKind.mood ||
      HabitKind.journal ||
      HabitKind.dua ||
      HabitKind.charity ||
      HabitKind.water ||
      HabitKind.diet ||
      HabitKind.fasting ||
      HabitKind.sleep ||
      HabitKind.earlyRise =>
        smallest,
    };
  }

  static int? _smallestTarget(HabitKind kind) {
    return switch (kind) {
      HabitKind.book => 2,
      HabitKind.quran => 1,
      HabitKind.study ||
      HabitKind.sport ||
      HabitKind.running ||
      HabitKind.walk ||
      HabitKind.language ||
      HabitKind.family =>
        10,
      HabitKind.zikr => 33,
      HabitKind.mood ||
      HabitKind.journal ||
      HabitKind.dua ||
      HabitKind.charity ||
      HabitKind.diet ||
      HabitKind.fasting ||
      HabitKind.sleep ||
      HabitKind.earlyRise =>
        1,
      HabitKind.water => 6,
      HabitKind.custom => 5,
    };
  }

  /// When the day usually has room for this, as minutes from midnight.
  /// A starting point the user can move, not a prescription.
  static int? defaultTimeOf(HabitKind kind) {
    return switch (kind) {
      HabitKind.earlyRise => 5 * 60, // the alarm the day hangs on
      HabitKind.zikr => 6 * 60, // after the dawn prayer
      HabitKind.quran => 6 * 60 + 30,
      HabitKind.sport || HabitKind.running => 7 * 60 + 30,
      HabitKind.walk => 18 * 60,
      HabitKind.family || HabitKind.charity => 19 * 60,
      HabitKind.study || HabitKind.language => 20 * 60,
      HabitKind.book => 21 * 60,
      HabitKind.mood || HabitKind.journal => 21 * 60 + 30,
      HabitKind.sleep => 22 * 60 + 30,
      HabitKind.dua => 12 * 60,
      HabitKind.custom => 12 * 60,
      // All day long, or fixed by the day itself: a reminder would be
      // noise.
      HabitKind.water || HabitKind.diet || HabitKind.fasting => null,
    };
  }

  /// A weak area becomes the habit that actually moves it. Prayer maps to
  /// dhikr because the prayers themselves are counted by the prayer screen,
  /// not by a widget; work maps to study because strengthening work, day to
  /// day, is learning.
  static List<HabitKind> _kindsOfArea(FocusArea area) {
    return switch (area) {
      FocusArea.prayer => const [HabitKind.zikr],
      FocusArea.quran => const [HabitKind.quran],
      FocusArea.health => const [HabitKind.sport, HabitKind.water],
      FocusArea.family => const [HabitKind.family],
      FocusArea.work => const [HabitKind.study],
      FocusArea.study => const [HabitKind.study, HabitKind.book],
      FocusArea.sleep => const [HabitKind.sleep],
      FocusArea.mood => const [HabitKind.mood],
    };
  }

  /// What an interest tracks. Public because the screen labels a chip with
  /// the same name the widget will carry.
  static HabitKind kindOfInterest(Interest interest) {
    return switch (interest) {
      Interest.quran => HabitKind.quran,
      Interest.zikr => HabitKind.zikr,
      Interest.book => HabitKind.book,
      Interest.study => HabitKind.study,
      Interest.sport => HabitKind.sport,
      Interest.water => HabitKind.water,
      Interest.family => HabitKind.family,
      Interest.sleep => HabitKind.sleep,
      Interest.mood => HabitKind.mood,
    };
  }

  /// What a day of this work tends to be short of. A guess, and the weakest
  /// of the three inputs — it only fills a plan the user left thin.
  static List<HabitKind> _kindsOfOccupation(Occupation? occupation) {
    return switch (occupation) {
      Occupation.student => const [HabitKind.study, HabitKind.book],
      Occupation.teacher => const [HabitKind.book, HabitKind.water],
      // Sitting all day: the body is what the day is missing, not thinking
      // time.
      Occupation.office || Occupation.it => const [
          HabitKind.sport,
          HabitKind.water,
        ],
      Occupation.business => const [HabitKind.sport, HabitKind.mood],
      // Shift work: sleep first, then the water nobody drinks on a ward.
      Occupation.medical => const [HabitKind.sleep, HabitKind.water],
      // On their feet all day: rest and something that is not physical.
      Occupation.labour => const [HabitKind.sleep, HabitKind.book],
      Occupation.driver => const [HabitKind.sport, HabitKind.water],
      Occupation.homemaker => const [HabitKind.mood, HabitKind.sport],
      Occupation.religious => const [HabitKind.quran, HabitKind.book],
      Occupation.other => const [HabitKind.book],
      null => const [],
    };
  }
}
