/// The account session: signed out (the app works fully offline), or signed
/// in, in which case the sync engine runs against the API.
///
/// - The refresh token is in secure storage ([RefreshTokenStore]); the
///   access token only in memory, renewed on demand by [AuthController
///   .accessToken] with a single in-flight refresh at a time.
/// - A refresh the server rejects ends the session
///   ([AuthSignedOut.sessionExpired]); a network failure does not.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../sync/outbox.dart';
import '../sync/sync_engine.dart';
import 'auth_api.dart';
import 'local_account_store.dart';
import 'refresh_token_store.dart';

sealed class AuthState {
  const AuthState();
}

/// Reading the saved session at startup.
final class AuthRestoring extends AuthState {
  const AuthRestoring();
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.sessionExpired = false});

  /// True when the server ended the session (not the user).
  final bool sessionExpired;
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn({required this.userId, required this.email});

  final String userId;
  final String email;
}

/// The current instant for token expiry. Overridden in tests.
final authClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class AuthController extends Notifier<AuthState> {
  String? _accessToken;
  DateTime? _accessExpiresAt;
  Future<String?>? _refreshing;

  /// Renew the access token this long before it actually expires.
  static const Duration _expiryMargin = Duration(seconds: 30);

  AuthApi get _api => ref.read(authApiProvider);
  RefreshTokenStore get _tokens => ref.read(refreshTokenStoreProvider);
  LocalAccountStore get _account =>
      LocalAccountStore(ref.read(appDatabaseProvider));
  SyncStateStore get _syncState =>
      SyncStateStore(ref.read(appDatabaseProvider));
  DateTime get _now => ref.read(authClockProvider)();

  @override
  AuthState build() {
    unawaited(_restore());
    return const AuthRestoring();
  }

  Future<void> _restore() async {
    try {
      final refreshToken = await _tokens.read();
      final account = await _account.read();
      // A sign-in that finished meanwhile wins over the stored state.
      if (!ref.mounted || state is! AuthRestoring) return;
      if (refreshToken != null && account != null) {
        state = AuthSignedIn(userId: account.userId, email: account.email);
        unawaited(ref.read(syncStatusProvider.notifier).runNow());
      } else {
        state = const AuthSignedOut();
      }
    } catch (error) {
      debugPrint('Saved session not restored: ${error.runtimeType}');
      if (ref.mounted && state is AuthRestoring) {
        state = const AuthSignedOut();
      }
    }
  }

  /// Throws [AuthApiException] when the server refuses or is unreachable.
  Future<void> signIn({required String email, required String password}) async {
    final deviceId = await _syncState.getOrCreateDeviceId();
    final tokens = await _api.login(
      email: email.trim(),
      password: password,
      deviceId: deviceId,
    );
    final user = await _api.me(tokens.accessToken);
    await _tokens.write(tokens.refreshToken);
    await _account.adopt(userId: user.id, email: user.email);
    _setAccess(tokens);
    state = AuthSignedIn(userId: user.id, email: user.email);
    unawaited(ref.read(syncStatusProvider.notifier).runNow(force: true));
  }

  /// Creates the account, then signs in with it.
  Future<void> signUp({
    required String email,
    required String password,
    required String locale,
  }) async {
    await _api.register(
        email: email.trim(), password: password, locale: locale);
    await signIn(email: email, password: password);
  }

  /// Revokes the refresh token when the server is reachable and forgets the
  /// session either way. The data stays on the device.
  Future<void> signOut() async {
    final refreshToken = await _readRefreshToken();
    if (refreshToken != null) {
      try {
        await _api.logout(refreshToken: refreshToken);
      } on AuthApiException {
        // Best effort: the token expires on its own.
      }
    }
    await _clearSession();
    if (ref.mounted) state = const AuthSignedOut();
  }

  /// An access token for an API call, renewed first when it is missing,
  /// about to expire or [forceRefresh] is set. `null` when signed out or
  /// when no token could be obtained.
  Future<String?> accessToken({bool forceRefresh = false}) {
    if (state is! AuthSignedIn) return Future.value(null);
    final token = _accessToken;
    final expiresAt = _accessExpiresAt;
    if (!forceRefresh &&
        token != null &&
        expiresAt != null &&
        _now.isBefore(expiresAt.subtract(_expiryMargin))) {
      return Future.value(token);
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _refresh() async {
    final refreshToken = await _readRefreshToken();
    if (refreshToken == null) {
      await _expire();
      return null;
    }
    try {
      final tokens = await _api.refresh(
        refreshToken: refreshToken,
        deviceId: await _syncState.getOrCreateDeviceId(),
      );
      await _tokens.write(tokens.refreshToken);
      _setAccess(tokens);
      return tokens.accessToken;
    } on AuthApiException catch (error) {
      if (error.kind == AuthErrorKind.invalidCredentials) await _expire();
      return null;
    }
  }

  Future<void> _expire() async {
    await _clearSession();
    if (ref.mounted) state = const AuthSignedOut(sessionExpired: true);
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    _accessExpiresAt = null;
    try {
      await _tokens.clear();
    } catch (error) {
      debugPrint('Refresh token not cleared: ${error.runtimeType}');
    }
    await _account.release();
  }

  void _setAccess(AuthTokens tokens) {
    _accessToken = tokens.accessToken;
    _accessExpiresAt = _now.add(tokens.expiresIn);
  }

  Future<String?> _readRefreshToken() async {
    try {
      return await _tokens.read();
    } catch (error) {
      debugPrint('Refresh token not read: ${error.runtimeType}');
      return null;
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
