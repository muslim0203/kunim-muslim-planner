import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/auth/auth_api.dart';
import 'package:kunim/core/auth/auth_controller.dart';
import 'package:kunim/core/auth/local_account_store.dart';
import 'package:kunim/core/auth/refresh_token_store.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/outbox.dart';
import 'package:kunim/core/sync/sync_api.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/mood/data/mood_log_repository.dart';

import '../../helpers/fake_auth.dart';
import '../../sync/sync_engine_fake_server.dart';

void main() {
  late AppDatabase db;
  late FakeAuthApi api;
  late MemoryRefreshTokenStore tokens;
  late DateTime now;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    api = FakeAuthApi();
    tokens = MemoryRefreshTokenStore();
    now = DateTime.utc(2026, 9, 14, 12);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authApiProvider.overrideWithValue(api),
        refreshTokenStoreProvider.overrideWithValue(tokens),
        syncApiProvider.overrideWithValue(FakeSyncServer()),
        authClockProvider.overrideWithValue(() => now),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  AuthController controller() =>
      container.read(authControllerProvider.notifier);
  AuthState state() => container.read(authControllerProvider);

  /// Lets the unawaited restore / sync work finish.
  Future<void> settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> signIn() async {
    await controller()
        .signIn(email: ' aziza@example.com ', password: 'secret123');
    await settle();
  }

  test('without a saved session the app is signed out', () async {
    state();
    await settle();

    expect(state(), isA<AuthSignedOut>());
  });

  test('a saved session is restored', () async {
    tokens.value = 'r0';
    await LocalAccountStore(db)
        .adopt(userId: api.user.id, email: api.user.email);

    state();
    await settle();

    expect(state(), isA<AuthSignedIn>());
    expect((state() as AuthSignedIn).email, api.user.email);
  });

  test('signing in stores the session and adopts this device\'s data',
      () async {
    final repo = MoodLogRepository(db, onLocalWrite: () {});
    final before = await repo.saveForDay(const LocalDay(2026, 9, 13), score: 3);

    await signIn();

    expect(state(), isA<AuthSignedIn>());
    expect(tokens.value, 'r1');
    expect((await LocalAccountStore(db).read())?.userId, api.user.id);
    expect(api.lastDeviceId, await SyncStateStore(db).getDeviceId());

    Future<String?> ownerOf(String id) async =>
        (await (db.select(db.moodLogs)..where((l) => l.id.equals(id)))
                .getSingle())
            .userId;
    expect(await ownerOf(before.id), api.user.id);
    final after = await repo.saveForDay(const LocalDay(2026, 9, 14), score: 4);
    expect(await ownerOf(after.id), api.user.id);
  });

  test('the access token is reused, then renewed once when it expires',
      () async {
    await signIn();
    expect(await controller().accessToken(), 'a1');
    expect(api.refreshCalls, 0);

    now = now.add(const Duration(minutes: 15));
    final renewed = await Future.wait([
      controller().accessToken(),
      controller().accessToken(),
    ]);

    expect(renewed, ['a2', 'a2']);
    expect(api.refreshCalls, 1);
    expect(tokens.value, 'r2');
  });

  test('a refresh the server rejects ends the session', () async {
    await signIn();
    api.refreshError = AuthErrorKind.invalidCredentials;

    expect(await controller().accessToken(forceRefresh: true), isNull);

    final ended = state();
    expect(ended, isA<AuthSignedOut>());
    expect((ended as AuthSignedOut).sessionExpired, isTrue);
    expect(tokens.value, isNull);
    expect(await LocalAccountStore(db).read(), isNull);
  });

  test('a network failure during refresh keeps the session', () async {
    await signIn();
    api.refreshError = AuthErrorKind.network;

    expect(await controller().accessToken(forceRefresh: true), isNull);

    expect(state(), isA<AuthSignedIn>());
    expect(tokens.value, 'r1');
  });

  test('signing out revokes the token and forgets the account', () async {
    await signIn();

    await controller().signOut();

    expect(api.lastLogoutToken, 'r1');
    expect(tokens.value, isNull);
    expect(await LocalAccountStore(db).read(), isNull);
    final signedOut = state();
    expect(signedOut, isA<AuthSignedOut>());
    expect((signedOut as AuthSignedOut).sessionExpired, isFalse);
    expect(await controller().accessToken(), isNull);
  });

  test('a refused sign-in leaves the app signed out', () async {
    state();
    await settle();
    api.loginError = AuthErrorKind.invalidCredentials;

    await expectLater(
      controller().signIn(email: 'aziza@example.com', password: 'wrong-pass'),
      throwsA(isA<AuthApiException>()),
    );

    expect(state(), isA<AuthSignedOut>());
    expect(tokens.value, isNull);
  });

  test('signing up registers with the app language, then signs in', () async {
    await controller().signUp(
      email: 'aziza@example.com',
      password: 'secret123',
      locale: 'uz',
    );
    await settle();

    expect(api.registerCalls, 1);
    expect(api.lastRegisteredLocale, 'uz');
    expect(state(), isA<AuthSignedIn>());
  });

  test('deleting the account closes it on the server and signs out', () async {
    await signIn();
    await SyncStateStore(db).setCursor(42);

    await controller().deleteAccount(password: 'secret123');

    expect(api.deleteCalls, 1);
    expect(api.lastDeletePassword, 'secret123');
    expect(api.lastDeleteAccessToken, 'a1');
    final signedOut = state();
    expect(signedOut, isA<AuthSignedOut>());
    expect((signedOut as AuthSignedOut).sessionExpired, isFalse);
    expect(tokens.value, isNull);
    expect(await LocalAccountStore(db).read(), isNull);
    expect(await SyncStateStore(db).getCursor(), 0);
  });

  test('a wrong password keeps the account and the session', () async {
    await signIn();
    api.deleteError = AuthErrorKind.invalidCredentials;

    await expectLater(
      controller().deleteAccount(password: 'not-it'),
      throwsA(isA<AuthApiException>()),
    );

    expect(state(), isA<AuthSignedIn>());
    expect(tokens.value, 'r1');
  });
}
