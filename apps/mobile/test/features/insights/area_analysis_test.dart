// Reading which part of a life is slipping out of what the app recorded.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/insights/domain/area_insight.dart';
import 'package:kunim/features/onboarding/domain/onboarding_answers.dart';

/// 14 days of outcomes, oldest first. `true` done, `false` missed, `null`
/// nothing planned.
List<bool?> days({
  int done = 0,
  int missed = 0,
  int unplanned = 0,
  List<bool?> then = const [],
}) {
  return [
    for (var i = 0; i < unplanned; i++) null,
    for (var i = 0; i < done; i++) true,
    for (var i = 0; i < missed; i++) false,
    ...then,
  ];
}

AreaObservation observation({
  FocusArea area = FocusArea.health,
  String title = 'Sport',
  String? habitId = 'h-1',
  int? reminderMinutes,
  bool everMetTarget = true,
  required List<bool?> outcomes,
}) {
  return AreaObservation(
    area: area,
    title: title,
    habitId: habitId,
    reminderMinutes: reminderMinutes,
    everMetTarget: everMetTarget,
    days: outcomes,
  );
}

AreaInsight only(List<AreaInsight> insights, FocusArea area) =>
    insights.firstWhere((insight) => insight.area == area);

void main() {
  test('an area with nothing recorded is an absence, not a failure', () {
    final insights = AreaAnalysis.compute(
      observations: const [],
      wanted: const [FocusArea.quran],
    );

    final quran = only(insights, FocusArea.quran);
    expect(quran.state, AreaState.untouched);
    expect(quran.advice, AreaAdvice.addWidget);
    expect(quran.donePercent, 0);
    expect(quran.plannedDays, 0);
  });

  test('done nearly every planned day reads as strong', () {
    final insights = AreaAnalysis.compute(
      observations: [
        observation(outcomes: days(done: 13, missed: 1)),
      ],
    );

    final health = only(insights, FocusArea.health);
    expect(health.state, AreaState.strong);
    expect(health.advice, AreaAdvice.keepGoing);
    expect(health.donePercent, 93);
  });

  test('a target never once reached is the target, not the person', () {
    final insights = AreaAnalysis.compute(
      observations: [
        observation(outcomes: days(missed: 14), everMetTarget: false),
      ],
    );

    final health = only(insights, FocusArea.health);
    expect(health.state, AreaState.slipping);
    expect(health.advice, AreaAdvice.lowerTarget);
  });

  test('slipping at a set hour, and falling, is about the hour', () {
    final insights = AreaAnalysis.compute(
      observations: [
        observation(
          reminderMinutes: 7 * 60,
          // The first week went well, this one did not.
          outcomes: days(done: 5, missed: 2, then: days(missed: 7)),
        ),
      ],
    );

    final health = only(insights, FocusArea.health);
    expect(health.state, AreaState.slipping);
    expect(health.trend, lessThan(0));
    expect(health.advice, AreaAdvice.moveTime);
  });

  test('something that was going and stopped is asked to start again', () {
    final insights = AreaAnalysis.compute(
      observations: [
        observation(outcomes: days(done: 4, missed: 10)),
      ],
    );

    final health = only(insights, FocusArea.health);
    expect(health.state, AreaState.slipping);
    expect(health.advice, AreaAdvice.startAgain);
  });

  test('holding up but falling fast gets a nudge, not a verdict', () {
    final insights = AreaAnalysis.compute(
      observations: [
        observation(
          reminderMinutes: 21 * 60,
          // Last week 7/7, this week 3/7: still above half, clearly falling.
          outcomes: days(done: 7, then: days(done: 3, missed: 4)),
        ),
      ],
    );

    final health = only(insights, FocusArea.health);
    expect(health.state, AreaState.steady);
    expect(health.trend, lessThanOrEqualTo(-AreaAnalysis.fallingPoints));
    expect(health.advice, AreaAdvice.moveTime);
  });

  test('a day nobody planned is never counted as missed', () {
    final insights = AreaAnalysis.compute(
      observations: [
        observation(outcomes: days(unplanned: 10, done: 4)),
      ],
    );

    final health = only(insights, FocusArea.health);
    expect(health.plannedDays, 4);
    expect(health.doneDays, 4);
    expect(health.state, AreaState.strong);
  });

  test('the weakest widget is the one the area is really about', () {
    final insights = AreaAnalysis.compute(
      observations: [
        observation(
          title: 'Suv',
          habitId: 'h-water',
          outcomes: days(done: 14),
        ),
        observation(
          title: 'Sport',
          habitId: 'h-sport',
          outcomes: days(missed: 14),
        ),
      ],
    );

    final health = only(insights, FocusArea.health);
    expect(health.title, 'Sport');
    expect(health.habitId, 'h-sport');
    // Both widgets count towards the area's own share.
    expect(health.plannedDays, 28);
    expect(health.doneDays, 14);
  });

  test('the weakest area is the one put first', () {
    final insights = AreaAnalysis.compute(
      observations: [
        observation(area: FocusArea.quran, outcomes: days(done: 14)),
        observation(area: FocusArea.sleep, outcomes: days(done: 8, missed: 6)),
        observation(area: FocusArea.health, outcomes: days(missed: 14)),
      ],
      wanted: const [FocusArea.family],
    );

    expect(
      insights.map((insight) => insight.area).toList(),
      [
        FocusArea.health, // slipping
        FocusArea.family, // nothing there at all
        FocusArea.sleep, // steady
        FocusArea.quran, // strong
      ],
    );
  });

  test('a first week alone has no trend to report', () {
    final insights = AreaAnalysis.compute(
      observations: [
        observation(outcomes: days(unplanned: 7, done: 5, missed: 2)),
      ],
    );

    // Nothing to compare the week against, so the trend stays at zero
    // instead of inventing a direction.
    expect(only(insights, FocusArea.health).trend, 0);
  });
}
