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
  late MemoryRefreshTokenStore tokens;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    api = FakeAuthApi();
    tokens = MemoryRefreshTokenStore();
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
          refreshTokenStoreProvider.overrideWithValue(tokens),
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

  Future<void> fill(
    WidgetTester tester,
    AppLocalizations l10n, {
    required String email,
    required String password,
  }) async {
    await tester.enterText(
      find.widgetWithText(TextField, l10n.authEmailLabel),
      email,
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.authPasswordLabel),
      password,
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  testWidgets('signing in shows the account and its sync state', (
    tester,
  ) async {
    final l10n = await pumpAccount(tester);

    await fill(tester, l10n, email: 'aziza@example.com', password: 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, l10n.authSignInButton));
    await _pumpFrames(tester, 20);

    expect(find.text(l10n.accountSignedIn), findsOneWidget);
    expect(find.text(api.user.email), findsOneWidget);
    expect(find.text(l10n.syncNow), findsOneWidget);
    expect(tokens.value, 'r1');
    await unmount(tester);
  });

  testWidgets('wrong credentials are reported without revealing the email',
      (tester) async {
    api.loginError = AuthErrorKind.invalidCredentials;
    final l10n = await pumpAccount(tester);

    await fill(tester, l10n, email: 'aziza@example.com', password: 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, l10n.authSignInButton));
    await _pumpFrames(tester);

    expect(find.text(l10n.authErrorInvalidCredentials), findsOneWidget);
    expect(find.text(l10n.accountSignedIn), findsNothing);
    await unmount(tester);
  });

  testWidgets('the form checks the input before calling the server', (
    tester,
  ) async {
    final l10n = await pumpAccount(tester);

    await fill(tester, l10n, email: 'not-an-email', password: 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, l10n.authSignInButton));
    await _pumpFrames(tester);
    expect(find.text(l10n.authErrorInvalidEmail), findsOneWidget);

    await tester
        .tap(find.text('${l10n.authNoAccount} ${l10n.authSignUpTitle}'));
    await _pumpFrames(tester);
    await fill(tester, l10n, email: 'aziza@example.com', password: 'secret123');
    await tester.enterText(
      find.widgetWithText(TextField, l10n.authConfirmPasswordLabel),
      'different1',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.authSignUpButton));
    await _pumpFrames(tester);

    expect(find.text(l10n.authErrorPasswordsMismatch), findsOneWidget);
    expect(api.loginCalls + api.registerCalls, 0);
    await unmount(tester);
  });

  testWidgets('signing out asks first, then returns to the sign-in form', (
    tester,
  ) async {
    final l10n = await pumpAccount(tester);
    await fill(tester, l10n, email: 'aziza@example.com', password: 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, l10n.authSignInButton));
    await _pumpFrames(tester, 20);

    await tester.tap(find.text(l10n.authSignOut));
    await _pumpFrames(tester);
    expect(find.text(l10n.accountSignOutConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.authSignOut).last);
    await _pumpFrames(tester, 20);

    expect(find.widgetWithText(FilledButton, l10n.authSignInButton),
        findsOneWidget);
    expect(api.logoutCalls, 1);
    expect(tokens.value, isNull);
    await unmount(tester);
  });

  testWidgets('deleting the account asks for the password, then signs out',
      (tester) async {
    final l10n = await pumpAccount(tester);
    await fill(tester, l10n, email: 'aziza@example.com', password: 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, l10n.authSignInButton));
    await _pumpFrames(tester, 20);

    await tester.tap(find.text(l10n.accountDelete));
    await _pumpFrames(tester);
    expect(find.text(l10n.accountDeleteTitle), findsOneWidget);
    final confirm =
        find.widgetWithText(FilledButton, l10n.accountDeleteConfirm);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    final passwordField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

    api.deleteError = AuthErrorKind.invalidCredentials;
    await tester.enterText(passwordField, 'not-it');
    await _pumpFrames(tester, 2);
    await tester.tap(confirm);
    await _pumpFrames(tester);
    expect(find.text(l10n.accountDeleteWrongPassword), findsOneWidget);

    api.deleteError = null;
    await tester.enterText(passwordField, 'secret123');
    await _pumpFrames(tester, 2);
    await tester.tap(confirm);
    await _pumpFrames(tester, 20);

    expect(api.lastDeletePassword, 'secret123');
    expect(find.text(l10n.accountDeleted), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, l10n.authSignInButton),
      findsOneWidget,
    );
    expect(tokens.value, isNull);
    await unmount(tester);
  });
}
