// Resetting a forgotten password from the sign-in form: ask for a code, then
// set the new password with it.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/auth/auth_api.dart';
import 'package:kunim/core/auth/refresh_token_store.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_api.dart';
import 'package:kunim/features/account/presentation/account_screen.dart';

import '../../helpers/fake_auth.dart';
import '../../sync/sync_engine_fake_server.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late AppDatabase db;
  late FakeAuthApi api;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    api = FakeAuthApi();
  });
  tearDown(() => db.close());

  Future<AppLocalizations> pumpAccount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authApiProvider.overrideWithValue(api),
          refreshTokenStoreProvider.overrideWithValue(MemoryRefreshTokenStore()),
          syncApiProvider.overrideWithValue(FakeSyncServer()),
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
          home: const AccountScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);
    return AppLocalizations.of(tester.element(find.byType(AccountScreen)));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  /// Opens the sheet with the address already typed into the sign-in form.
  Future<void> openSheet(WidgetTester tester, AppLocalizations l10n) async {
    await tester.enterText(
      find.widgetWithText(TextField, l10n.authEmailLabel),
      'aziza@example.com',
    );
    await _pumpFrames(tester, 2);
    await tester.tap(find.text(l10n.authForgotPassword));
    await _pumpFrames(tester);
  }

  Finder inSheet(Type type) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.byType(type));

  testWidgets('asks for a code, then sets the new password', (tester) async {
    final l10n = await pumpAccount(tester);
    await openSheet(tester, l10n);

    // The address carries over from the sign-in form.
    expect(find.text(l10n.authForgotTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.authForgotSend));
    await _pumpFrames(tester);

    expect(api.forgotCalls, 1);
    expect(api.lastForgotEmail, 'aziza@example.com');
    expect(find.text(l10n.authForgotSent), findsOneWidget);

    // Second step: the code from the email and the new password.
    await tester.enterText(
      find.widgetWithText(TextField, l10n.authResetCodeLabel),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.authResetNewPassword),
      'yangi-parol-123',
    );
    await _pumpFrames(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, l10n.authResetSubmit));
    await _pumpFrames(tester, 20);

    expect(api.lastResetCode, '123456');
    expect(api.lastResetPassword, 'yangi-parol-123');
    expect(find.text(l10n.authResetDone), findsOneWidget);
    // Back on the sign-in form, ready for the new password.
    expect(find.byType(BottomSheet), findsNothing);
    await unmount(tester);
  });

  testWidgets('a wrong code is reported without closing the sheet', (
    tester,
  ) async {
    final l10n = await pumpAccount(tester);
    await openSheet(tester, l10n);
    await tester.tap(find.widgetWithText(FilledButton, l10n.authForgotSend));
    await _pumpFrames(tester);
    api.resetError = AuthErrorKind.invalidInput;

    await tester.enterText(
      find.widgetWithText(TextField, l10n.authResetCodeLabel),
      '000000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.authResetNewPassword),
      'yangi-parol-123',
    );
    await _pumpFrames(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, l10n.authResetSubmit));
    await _pumpFrames(tester);

    expect(find.text(l10n.authResetErrorCode), findsOneWidget);
    expect(find.text(l10n.authResetDone), findsNothing);
    expect(inSheet(TextField), findsNWidgets(3));
    await unmount(tester);
  });

  testWidgets('a short code or password cannot be submitted', (tester) async {
    final l10n = await pumpAccount(tester);
    await openSheet(tester, l10n);
    await tester.tap(find.widgetWithText(FilledButton, l10n.authForgotSend));
    await _pumpFrames(tester);

    final submit = find.widgetWithText(FilledButton, l10n.authResetSubmit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, l10n.authResetCodeLabel),
      '12345',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.authResetNewPassword),
      'qisqa',
    );
    await _pumpFrames(tester, 2);

    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(api.resetCalls, 0);
    await unmount(tester);
  });

  testWidgets('a network failure while asking is reported', (tester) async {
    api.forgotError = AuthErrorKind.network;
    final l10n = await pumpAccount(tester);
    await openSheet(tester, l10n);

    await tester.tap(find.widgetWithText(FilledButton, l10n.authForgotSend));
    await _pumpFrames(tester);

    expect(find.text(l10n.authErrorNetwork), findsOneWidget);
    expect(find.text(l10n.authForgotSent), findsNothing);
    await unmount(tester);
  });
}
