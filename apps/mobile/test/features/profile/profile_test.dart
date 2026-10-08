// The account-details screen and the model behind it.
//
// The rule worth protecting here: height is a profile field, weight is not.
// Weight is a dated `health_logs` measurement, so a copy on the profile
// would go stale and then disagree with the weight chart.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/features/profile/application/profile_providers.dart';
import 'package:kunim/features/profile/data/profile_api.dart';
import 'package:kunim/features/profile/domain/profile.dart';
import 'package:kunim/features/profile/presentation/profile_screen.dart';

const _profile = Profile(
  id: 'u-1',
  email: 'muslim@example.com',
  displayName: 'Muslimjon Zarifjonov',
  nickname: 'muslim',
  birthYear: 1995,
  heightCm: 178,
);

class _FakeApi implements ProfileApi {
  _FakeApi({this.throws});

  final ProfileErrorKind? throws;
  Map<String, Object?>? lastUpdate;

  @override
  Future<Profile> fetch() async {
    if (throws != null) throw ProfileApiException(throws!);
    return _profile;
  }

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
  }) async {
    if (throws != null) throw ProfileApiException(throws!);
    lastUpdate = {
      'display_name': displayName,
      'nickname': nickname,
      'birth_year': birthYear,
      'height_cm': heightCm,
      'clear_height': clearHeight,
    };
    return _profile;
  }
}

Future<void> _pump(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('Profile model', () {
    test('stores the year of birth and derives the age from it', () {
      // An age stored as a number is wrong by the next birthday.
      expect(_profile.ageIn(DateTime(2026, 1, 1)), 31);
      expect(_profile.ageIn(DateTime(2030, 1, 1)), 35);
    });

    test('a year that cannot be a birth year has no age', () {
      // The form asks for this one while the user is still typing, so "19"
      // and a year in the future must come back empty, not absurd.
      final today = DateTime(2026, 6, 1);
      expect(Profile.ageFromBirthYear(1995, today), 31);
      expect(Profile.ageFromBirthYear(2030, today), isNull);
      expect(Profile.ageFromBirthYear(19, today), isNull);
    });

    test('an unknown birth year has no age', () {
      const without = Profile(id: 'u', email: 'a@b.com');
      expect(without.ageIn(DateTime(2026)), isNull);
    });

    test('initials come from the name, then the handle, then the email', () {
      expect(_profile.initials, 'MZ');
      expect(
        const Profile(id: 'u', email: 'a@b.com', nickname: 'muslim').initials,
        'MU',
      );
      expect(const Profile(id: 'u', email: 'zarif@b.com').initials, 'ZA');
    });

    test('the model carries no weight field at all', () {
      // Weight belongs to `health_logs`; this is the guard against someone
      // adding a second, staler copy here.
      final json = {
        'id': 'u',
        'email': 'a@b.com',
        'weight_kg': 72.5,
      };
      final parsed = Profile.fromJson(json);
      expect(parsed.email, 'a@b.com');
      expect(
        parsed.toString().contains('72.5'),
        isFalse,
        reason: 'a weight sent by a server must not land on the profile',
      );
    });
  });

  group('Profile screen', () {
    Future<AppLocalizations> pumpScreen(
      WidgetTester tester,
      _FakeApi api, {
      double? loggedWeight,
      List<double>? weightsWritten,
    }) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileApiProvider.overrideWithValue(api),
            // Weight comes from `health_logs`, so the real providers would
            // open a Drift database. Overriding them keeps this a test of
            // the profile screen and nothing else.
            latestWeightProvider.overrideWithValue(
              AsyncValue.data(loggedWeight),
            ),
            weightWriterProvider.overrideWithValue(
              (double kilograms) async => weightsWritten?.add(kilograms),
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
            home: const ProfileScreen(),
          ),
        ),
      );
      // The provider's future settles on the real event loop; `pump` alone
      // only advances the fake clock, so an error would still be "loading".
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _pump(tester);
      return AppLocalizations.of(tester.element(find.byType(ProfileScreen)));
    }

    testWidgets('shows the stored details, and the age under the year', (
      tester,
    ) async {
      final l10n = await pumpScreen(tester, _FakeApi());

      expect(find.text('Muslimjon Zarifjonov'), findsOneWidget);
      expect(find.text('muslim'), findsOneWidget);
      expect(find.text('1995'), findsOneWidget);
      expect(find.text('178'), findsOneWidget);
      expect(find.text('muslim@example.com'), findsOneWidget);
      expect(find.text('MZ'), findsOneWidget);
      expect(
        find.text(l10n.profileAgeNow(_profile.ageIn(DateTime.now())!)),
        findsOneWidget,
      );
    });

    testWidgets('an emptied field is cleared, not left as it was', (
      tester,
    ) async {
      final api = _FakeApi();
      final l10n = await pumpScreen(tester, api);

      await tester.enterText(find.widgetWithText(TextField, '178'), '');
      await tester.tap(find.text(l10n.profileSave));
      await _pump(tester);

      expect(api.lastUpdate?['clear_height'], isTrue);
      expect(api.lastUpdate?['height_cm'], isNull);
    });

    testWidgets(
        'an edited weight is written as a health log, not a profile '
        'field', (tester) async {
      // This is the whole reason weight is not on the profile: the number
      // the user types here has to land in the same dated rows the weight
      // chart is drawn from.
      final api = _FakeApi();
      final written = <double>[];
      final l10n = await pumpScreen(
        tester,
        api,
        loggedWeight: 71,
        weightsWritten: written,
      );

      expect(find.text('71'), findsOneWidget, reason: 'the last log shows');

      await tester.enterText(find.widgetWithText(TextField, '71'), '72.5');
      await tester.tap(find.text(l10n.profileSave));
      await _pump(tester);

      expect(written, [72.5]);
      expect(
        api.lastUpdate?.containsKey('weight_kg'),
        isFalse,
        reason: 'weight must never be sent to the profile endpoint',
      );
    });

    testWidgets('a taken username is reported, not swallowed', (tester) async {
      final l10n = await pumpScreen(
        tester,
        _FakeApi(throws: ProfileErrorKind.nicknameTaken),
      );

      expect(find.text(l10n.profileErrorNicknameTaken), findsOneWidget);
    });

    testWidgets('a failed load offers a retry rather than an empty form', (
      tester,
    ) async {
      final l10n = await pumpScreen(
        tester,
        _FakeApi(throws: ProfileErrorKind.network),
      );

      expect(find.text(l10n.profileErrorNetwork), findsOneWidget);
      expect(find.text(l10n.profileRetry), findsOneWidget);
    });
  });
}
