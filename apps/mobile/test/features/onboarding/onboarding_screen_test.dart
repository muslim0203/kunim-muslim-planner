// The questions asked at sign-up, and the day they produce.
//
// Rows are read back with one-shot queries, never `watch().first` (a Drift
// stream inside `testWidgets`' fake-async zone waits on timers that only
// advance when the test pumps).
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/habits/domain/habit_kind.dart';
import 'package:kunim/features/onboarding/presentation/onboarding_screen.dart';
import 'package:kunim/features/profile/data/profile_api.dart';
import 'package:kunim/features/profile/domain/profile.dart';

/// Records what the onboarding sends to the account.
class FakeProfileApi implements ProfileApi {
  String? occupation;
  List<String>? interests;
  List<String>? focusAreas;
  int? dailyMinutes;
  int updates = 0;
  ProfileErrorKind? failWith;

  @override
  Future<Profile> fetch() async => _profile();

  @override
  Future<Profile> update({
    String? displayName,
    String? nickname,
    int? birthYear,
    int? heightCm,
    bool clearDisplayName = false,
    bool clearNickname = false,
    bool clearBirthYear = false,
    bool clearHeight = false,
    String? occupation,
    List<String>? interests,
    List<String>? focusAreas,
    int? dailyMinutes,
  }) async {
    updates++;
    if (failWith != null) throw ProfileApiException(failWith!);
    this.occupation = occupation;
    this.interests = interests;
    this.focusAreas = focusAreas;
    this.dailyMinutes = dailyMinutes;
    return _profile();
  }

  Profile _profile() => Profile(
        id: 'u-1',
        email: 'aziza@example.com',
        occupation: occupation,
        interests: interests ?? const [],
        focusAreas: focusAreas ?? const [],
        dailyMinutes: dailyMinutes,
      );
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;
  late FakeProfileApi profiles;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    profiles = FakeProfileApi();
  });
  tearDown(() => db.close());

  Future<AppLocalizations> pumpOnboarding(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          profileApiProvider.overrideWithValue(profiles),
          syncTriggerSchedulerProvider.overrideWithValue(
            SyncTriggerScheduler(runSync: ({bool force = false}) async {}),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('uz'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          // Opened the way the app opens it — pushed over the screen the
          // user was on — so finishing really returns them to it.
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showOnboarding(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _pumpFrames(tester, 20);
    return AppLocalizations.of(tester.element(find.byType(OnboardingScreen)));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  Future<void> next(WidgetTester tester, AppLocalizations l10n) async {
    await tester.tap(find.widgetWithText(FilledButton, l10n.onboardingNext));
    await _pumpFrames(tester);
  }

  Future<List<Habit>> habits() =>
      (db.select(db.habits)..where((h) => h.deletedAt.isNull())).get();

  testWidgets('the answers become a day the user can edit', (tester) async {
    final l10n = await pumpOnboarding(tester);

    // 1. What they do all day.
    await tester.tap(find.text(l10n.onboardingWorkOffice));
    await _pumpFrames(tester, 2);
    await next(tester, l10n);

    // 2. An interest.
    await tester.tap(find.text(l10n.habitKindBook));
    await _pumpFrames(tester, 2);
    await next(tester, l10n);

    // 3. A weak area.
    await tester.tap(find.text(l10n.moduleHealth));
    await _pumpFrames(tester, 2);
    await next(tester, l10n);

    // 4. The minutes the day holds.
    await tester.tap(find.text(l10n.onboardingMinutesChoice(30)));
    await _pumpFrames(tester, 2);
    await next(tester, l10n);

    // The plan explains itself: the weak area comes first, and each line
    // says why it is there.
    expect(find.text(l10n.onboardingPlanTitle), findsWidgets);
    expect(find.textContaining(l10n.onboardingReasonFocus), findsWidgets);
    expect(find.textContaining(l10n.onboardingReasonInterest), findsWidgets);

    await tester.tap(
      find.widgetWithText(FilledButton, l10n.onboardingPlanAccept),
    );
    await _pumpFrames(tester, 20);

    final created = await habits();
    expect(created, isNotEmpty);
    expect(
      created.map((habit) => habit.kind),
      containsAll([HabitKind.sport.code, HabitKind.book.code]),
    );
    // Every widget carries the time its task usually fits in.
    expect(
      created
          .firstWhere((habit) => habit.kind == HabitKind.book.code)
          .reminderMinutes,
      21 * 60,
    );
    // And the answers reached the account.
    expect(profiles.occupation, 'office');
    expect(profiles.interests, ['book']);
    expect(profiles.focusAreas, ['health']);
    expect(profiles.dailyMinutes, 30);
    await unmount(tester);
  });

  testWidgets('a suggestion the user drops is never created', (tester) async {
    final l10n = await pumpOnboarding(tester);
    await next(tester, l10n); // no occupation
    await tester.tap(find.text(l10n.habitKindBook));
    await _pumpFrames(tester, 2);
    await tester.tap(find.text(l10n.habitKindSport));
    await _pumpFrames(tester, 2);
    await next(tester, l10n);
    await next(tester, l10n); // no weak area
    await next(tester, l10n); // the default budget

    // Drop the reading widget, keep the sport one.
    await tester.tap(
      find.widgetWithText(CheckboxListTile, l10n.habitKindBook),
    );
    await _pumpFrames(tester, 2);
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.onboardingPlanAccept),
    );
    await _pumpFrames(tester, 20);

    final created = await habits();
    expect(created.map((habit) => habit.kind), [HabitKind.sport.code]);
    await unmount(tester);
  });

  testWidgets('answering nothing creates nothing', (tester) async {
    final l10n = await pumpOnboarding(tester);

    for (var step = 0; step < 4; step++) {
      await next(tester, l10n);
    }

    expect(find.text(l10n.onboardingPlanEmpty), findsOneWidget);
    expect(await habits(), isEmpty);
    expect(profiles.updates, 0, reason: 'nothing to save');
    await unmount(tester);
  });

  testWidgets('the plan still stands when the account cannot be reached', (
    tester,
  ) async {
    profiles.failWith = ProfileErrorKind.network;
    final l10n = await pumpOnboarding(tester);
    await next(tester, l10n);
    await tester.tap(find.text(l10n.habitKindZikr));
    await _pumpFrames(tester, 2);
    await next(tester, l10n);
    await next(tester, l10n);
    await next(tester, l10n);
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.onboardingPlanAccept),
    );
    await _pumpFrames(tester, 20);

    // The widgets are on the device either way; the user is told what did
    // not happen rather than being shown a success that is not one.
    expect(await habits(), isNotEmpty);
    expect(find.text(l10n.onboardingAnswersNotSaved), findsOneWidget);
    await unmount(tester);
  });
}
