/// The request body of `POST /ai/analysis`: what this device measured.
///
/// The model is handed numbers, never raw records. Every field here is one
/// the user could count on their own grid, and the counts are exactly the
/// ones the offline analysis already put on screen
/// (`features/insights/domain/area_insight.dart`) — so the AI summary and
/// the cards under it can never disagree about the facts.
///
/// Two things are deliberate:
///
/// * **The vocabulary travels with the request.** `available_kinds` is what
///   *this build* can create, so the server never has to know. A later app
///   version that adds a widget kind starts getting proposals for it with
///   no server deploy.
/// * **Nothing is sent that the server did not ask for.** No logs, no dates,
///   no widget ids, no raw prayer marks. The server stores none of this: it
///   keeps token counts and money only (`ai_requests`).
library;

import '../../habits/domain/habit_kind.dart';
import '../../insights/domain/area_insight.dart';
import '../../onboarding/domain/onboarding_answers.dart';

/// One area's record, as the server's `AreaFact` wants it.
class AreaFactPayload {
  const AreaFactPayload({
    required this.area,
    required this.state,
    required this.plannedDays,
    required this.doneDays,
    required this.trend,
    required this.everMetTarget,
    this.widget,
    this.dailyTarget,
    this.reminderMinutes,
  });

  final FocusArea area;
  final AreaState state;

  /// The widget the area's trouble is about, as the user named it. Free text
  /// they typed; the server quotes it into the prompt as data.
  final String? widget;

  final int plannedDays;
  final int doneDays;
  final int trend;
  final bool everMetTarget;
  final int? dailyTarget;
  final int? reminderMinutes;

  Map<String, dynamic> toJson() => {
        'area': area.slug,
        'state': state.name,
        if (widget != null && widget!.isNotEmpty)
          // The server's own limit, applied here so a long title is trimmed
          // rather than rejecting the whole request with a 422.
          'widget': widget!.length <= 80 ? widget : widget!.substring(0, 80),
        'planned_days': plannedDays.clamp(0, 400),
        'done_days': doneDays.clamp(0, 400),
        'trend': trend.clamp(-100, 100),
        'ever_met_target': everMetTarget,
        if (dailyTarget != null) 'daily_target': dailyTarget!.clamp(1, 100000),
        if (reminderMinutes != null)
          'reminder_minutes': reminderMinutes!.clamp(0, 24 * 60 - 1),
      };
}

class AnalysisFacts {
  const AnalysisFacts({
    required this.windowDays,
    required this.locale,
    required this.areas,
    required this.availableKinds,
    this.occupation,
    this.interests = const [],
    this.focusAreas = const [],
    this.dailyMinutes,
  });

  final int windowDays;

  /// Which language to answer in — the locale the app is actually showing,
  /// not the account's. The user reads the answer on this device.
  final String locale;

  final List<AreaFactPayload> areas;
  final List<HabitKind> availableKinds;

  final Occupation? occupation;
  final List<Interest> interests;
  final List<FocusArea> focusAreas;
  final int? dailyMinutes;

  /// False when there is nothing worth paying for: no measured area and no
  /// area the user asked about. The server answers 422 in that case; this
  /// lets the screen say "not enough recorded yet" without a round trip.
  bool get hasSomethingToAnalyse => areas.isNotEmpty || focusAreas.isNotEmpty;

  /// The counts this analysis would be about, as one comparable string.
  ///
  /// An analysis is a paid call, so it is kept after the numbers behind it
  /// move — but then the summary quotes one set of figures while the cards
  /// under it show another. Comparing this against the live facts tells the
  /// screen to say the summary is from an earlier moment instead of letting
  /// the two contradict each other in silence.
  String get countsDigest => [
        for (final area in areas)
          '${area.area.slug}:${area.doneDays}/${area.plannedDays}',
      ].join('|');

  Map<String, dynamic> toJson() => {
        'window_days': windowDays,
        'locale': locale,
        'areas': [for (final area in areas.take(12)) area.toJson()],
        if (occupation != null) 'occupation': occupation!.slug,
        'interests': [for (final interest in interests.take(24)) interest.slug],
        'focus_areas': [for (final area in focusAreas.take(24)) area.slug],
        if (dailyMinutes != null)
          'daily_minutes': DailyBudget.clamp(dailyMinutes),
        'available_kinds': [
          for (final kind in availableKinds.take(32)) kind.code,
        ],
      };

  /// Builds the request from what the offline analysis already worked out.
  ///
  /// [insights] are ordered weakest first, and only the first twelve are
  /// sent — the server's limit, and more than any screen shows anyway.
  /// [observations] supply the two numbers an insight does not carry: the
  /// daily amount and the reminder hour, both of which the model needs to
  /// say "this amount is too big" instead of "try harder".
  factory AnalysisFacts.from({
    required List<AreaInsight> insights,
    required List<AreaObservation> observations,
    required int windowDays,
    required String locale,
    OnboardingAnswers? answers,
  }) {
    return AnalysisFacts(
      windowDays: windowDays,
      locale: locale,
      areas: [
        for (final insight in insights)
          _factFor(insight, _matching(insight, observations)),
      ],
      availableKinds: proposableKinds,
      occupation: answers?.occupation,
      interests: answers?.interests.toList() ?? const [],
      focusAreas: answers?.focusAreas.toList() ?? const [],
      dailyMinutes: answers?.dailyMinutes,
    );
  }

  /// The widget kinds a proposal may name.
  ///
  /// [HabitKind.custom] is left out on purpose: it is a real kind, but a
  /// "custom" proposal describes nothing the user can picture before
  /// accepting it.
  static final List<HabitKind> proposableKinds = [
    for (final kind in HabitKind.values)
      if (kind != HabitKind.custom) kind,
  ];

  /// The observation an insight was built from — same area, same widget.
  static AreaObservation? _matching(
    AreaInsight insight,
    List<AreaObservation> observations,
  ) {
    for (final observation in observations) {
      if (observation.area == insight.area &&
          observation.habitId == insight.habitId) {
        return observation;
      }
    }
    return null;
  }

  static AreaFactPayload _factFor(
    AreaInsight insight,
    AreaObservation? observation,
  ) {
    return AreaFactPayload(
      area: insight.area,
      state: insight.state,
      widget: insight.title.isEmpty ? null : insight.title,
      plannedDays: insight.plannedDays,
      doneDays: insight.doneDays,
      trend: insight.trend,
      everMetTarget: observation?.everMetTarget ?? true,
      dailyTarget: observation?.dailyTarget,
      reminderMinutes: observation?.reminderMinutes,
    );
  }
}
