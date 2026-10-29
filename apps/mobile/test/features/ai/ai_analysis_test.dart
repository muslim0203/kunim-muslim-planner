// What the app sends the analyst, and what it will accept back.
//
// The two halves tested here are the ones that protect the user from a model
// answer: the request carries only numbers this device measured, and the
// answer is stripped of anything this build cannot honour exactly. Nothing
// here touches the network.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/ai/domain/ai_analysis.dart';
import 'package:kunim/features/ai/domain/analysis_facts.dart';
import 'package:kunim/features/habits/domain/habit_kind.dart';
import 'package:kunim/features/insights/domain/area_insight.dart';
import 'package:kunim/features/onboarding/domain/onboarding_answers.dart';

AreaInsight insight({
  FocusArea area = FocusArea.health,
  String title = 'Sport',
  String? habitId = 'h-1',
  int plannedDays = 14,
  int doneDays = 3,
  int trend = -30,
  AreaState state = AreaState.slipping,
  AreaAdvice advice = AreaAdvice.lowerTarget,
}) {
  return AreaInsight(
    area: area,
    title: title,
    habitId: habitId,
    plannedDays: plannedDays,
    doneDays: doneDays,
    trend: trend,
    state: state,
    advice: advice,
  );
}

AreaObservation observation({
  FocusArea area = FocusArea.health,
  String title = 'Sport',
  String? habitId = 'h-1',
  int? dailyTarget = 30,
  int? reminderMinutes = 7 * 60,
  bool everMetTarget = false,
}) {
  return AreaObservation(
    area: area,
    title: title,
    habitId: habitId,
    dailyTarget: dailyTarget,
    reminderMinutes: reminderMinutes,
    everMetTarget: everMetTarget,
    days: const [true, false, false],
  );
}

Map<String, dynamic> areaFact(Map<String, dynamic> json, String area) {
  final areas = (json['areas'] as List).cast<Map<String, dynamic>>();
  return areas.firstWhere((fact) => fact['area'] == area);
}

void main() {
  group('the request', () {
    test('carries the numbers the offline analysis already worked out', () {
      final json = AnalysisFacts.from(
        insights: [insight()],
        observations: [observation()],
        windowDays: 14,
        locale: 'uz',
      ).toJson();

      expect(json['window_days'], 14);
      expect(json['locale'], 'uz');

      final health = areaFact(json, 'health');
      expect(health['state'], 'slipping');
      expect(health['widget'], 'Sport');
      expect(health['planned_days'], 14);
      expect(health['done_days'], 3);
      expect(health['trend'], -30);
      // The two the insight does not carry: both come from the observation,
      // and both are what lets the model say the amount is too big.
      expect(health['daily_target'], 30);
      expect(health['reminder_minutes'], 7 * 60);
      expect(health['ever_met_target'], isFalse);
    });

    test('sends no widget name for the prayers, which have none', () {
      final json = AnalysisFacts.from(
        insights: [insight(area: FocusArea.prayer, title: '', habitId: null)],
        observations: [
          observation(
            area: FocusArea.prayer,
            title: '',
            habitId: null,
            dailyTarget: null,
            reminderMinutes: null,
          ),
        ],
        windowDays: 14,
        locale: 'uz',
      ).toJson();

      final prayer = areaFact(json, 'prayer');
      expect(prayer.containsKey('widget'), isFalse);
      expect(prayer.containsKey('daily_target'), isFalse);
      expect(prayer.containsKey('reminder_minutes'), isFalse);
    });

    test('trims a widget name longer than the server allows', () {
      final json = AnalysisFacts.from(
        insights: [insight(title: 'x' * 200)],
        observations: [observation(title: 'x' * 200)],
        windowDays: 14,
        locale: 'uz',
      ).toJson();

      expect((areaFact(json, 'health')['widget'] as String).length, 80);
    });

    test('offers every widget kind except the shapeless one', () {
      final json = AnalysisFacts.from(
        insights: [insight()],
        observations: [observation()],
        windowDays: 14,
        locale: 'uz',
      ).toJson();

      final kinds = (json['available_kinds'] as List).cast<String>();
      expect(kinds, contains('sport'));
      expect(kinds, contains('quran'));
      // A "custom" proposal describes nothing the user can picture before
      // accepting it.
      expect(kinds, isNot(contains('custom')));
    });

    test('passes the sign-up answers through as slugs', () {
      final json = AnalysisFacts.from(
        insights: [insight()],
        observations: [observation()],
        windowDays: 14,
        locale: 'ru',
        answers: const OnboardingAnswers(
          occupation: Occupation.it,
          interests: {Interest.book},
          focusAreas: {FocusArea.study},
          dailyMinutes: 30,
        ),
      ).toJson();

      expect(json['occupation'], 'it');
      expect(json['interests'], ['book']);
      expect(json['focus_areas'], ['study']);
      expect(json['daily_minutes'], 30);
    });

    test('knows there is nothing worth paying for', () {
      final nothing = AnalysisFacts.from(
        insights: const [],
        observations: const [],
        windowDays: 14,
        locale: 'uz',
      );
      expect(nothing.hasSomethingToAnalyse, isFalse);

      // An area the user asked about is reason enough, even with nothing
      // measured in it: "you asked for this and there is nothing here" is
      // worth saying.
      final asked = AnalysisFacts.from(
        insights: const [],
        observations: const [],
        windowDays: 14,
        locale: 'uz',
        answers: const OnboardingAnswers(focusAreas: {FocusArea.sleep}),
      );
      expect(asked.hasSomethingToAnalyse, isTrue);
    });
  });

  group('the answer', () {
    test('keeps the summary, the notes and the proposals', () {
      final analysis = AiAnalysis.fromJson(const {
        'summary': 'Sport uch kundan beri oqsayapti.',
        'areas': [
          {'area': 'health', 'note': 'Uch kun bajarilgan.', 'priority': 1},
        ],
        'widgets': [
          {
            'kind': 'sleep',
            'title': 'Erta yotish',
            'daily_target': 1,
            'reminder_minutes': 1320,
            'reason': 'Kech yotish sportni yeb qo‘yayapti.',
          },
        ],
      });

      expect(analysis.summary, 'Sport uch kundan beri oqsayapti.');
      expect(analysis.areas.single.area, FocusArea.health);
      expect(analysis.areas.single.priority, 1);
      expect(analysis.widgets.single.kind, HabitKind.sleep);
      expect(analysis.widgets.single.title, 'Erta yotish');
      expect(analysis.widgets.single.reminderMinutes, 1320);
    });

    test('puts the notes that need attention first', () {
      final analysis = AiAnalysis.fromJson(const {
        'summary': '',
        'areas': [
          {'area': 'study', 'note': 'Joyida.', 'priority': 3},
          {'area': 'health', 'note': 'Oqsayapti.', 'priority': 1},
        ],
        'widgets': [],
      });

      expect(
        [for (final note in analysis.areas) note.area],
        [FocusArea.health, FocusArea.study],
      );
    });

    test('drops a note about an area this build does not know', () {
      final analysis = AiAnalysis.fromJson(const {
        'summary': 'x',
        'areas': [
          {'area': 'finance', 'note': 'Pul.', 'priority': 1},
          {'area': 'health', 'note': 'Sport.', 'priority': 2},
        ],
        'widgets': [],
      });

      expect(analysis.areas.single.area, FocusArea.health);
    });

    test('drops a widget kind this build cannot create, never guesses', () {
      final analysis = AiAnalysis.fromJson(const {
        'summary': 'x',
        'areas': [],
        'widgets': [
          {
            'kind': 'meditation',
            'title': 'Meditatsiya',
            'daily_target': 10,
            'reminder_minutes': null,
            'reason': 'y',
          },
        ],
      });

      // The point of this test: an unknown kind must not come back as
      // HabitKind.custom, which would create a widget that is not what the
      // proposal described.
      expect(analysis.widgets, isEmpty);
    });

    test('drops a proposal with no title and clamps a wild amount', () {
      final analysis = AiAnalysis.fromJson(const {
        'summary': 'x',
        'areas': [],
        'widgets': [
          {
            'kind': 'water',
            'title': '   ',
            'daily_target': 8,
            'reminder_minutes': null,
            'reason': 'y',
          },
          {
            'kind': 'book',
            'title': 'Kitob',
            'daily_target': 999999999,
            'reminder_minutes': 99999,
            'reason': 'y',
          },
        ],
      });

      expect(analysis.widgets.single.kind, HabitKind.book);
      expect(analysis.widgets.single.dailyTarget, 100000);
      expect(analysis.widgets.single.reminderMinutes, 1439);
    });

    test('survives an answer that is missing everything', () {
      final analysis = AiAnalysis.fromJson(const {});
      expect(analysis.isEmpty, isTrue);
    });

    test('reads a stored proposal, payload and all', () {
      final proposal = AiProposal.fromJson(const {
        'id': 'p-1',
        'agent': 'analyst',
        'status': 'proposed',
        'model': 'claude-sonnet-5-5',
        'payload': {'summary': 'Salom', 'areas': [], 'widgets': []},
      });

      expect(proposal.id, 'p-1');
      expect(proposal.model, 'claude-sonnet-5-5');
      expect(proposal.analysis.summary, 'Salom');
    });

    test('the outcomes the server stores are spelled as it expects', () {
      expect(AiProposalOutcome.accepted.wire, 'accepted');
      expect(AiProposalOutcome.modified.wire, 'modified');
      expect(AiProposalOutcome.rejected.wire, 'rejected');
    });
  });
}
