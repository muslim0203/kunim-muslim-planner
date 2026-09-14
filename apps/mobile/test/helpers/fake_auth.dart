import 'package:kunim/core/auth/auth_api.dart';
import 'package:kunim/core/auth/refresh_token_store.dart';

class MemoryRefreshTokenStore implements RefreshTokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;
}

/// Issues tokens `a1`/`r1`, `a2`/`r2`, ... and records every call.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({
    this.user = const AuthUser(
      id: '22222222-2222-4222-8222-222222222222',
      email: 'aziza@example.com',
    ),
  });

  final AuthUser user;

  AuthErrorKind? registerError;
  AuthErrorKind? loginError;
  AuthErrorKind? refreshError;

  int registerCalls = 0;
  int loginCalls = 0;
  int refreshCalls = 0;
  int logoutCalls = 0;
  String? lastDeviceId;
  String? lastLogoutToken;
  String? lastRegisteredLocale;

  var _issued = 0;

  AuthTokens _nextTokens() {
    _issued++;
    return AuthTokens(
      accessToken: 'a$_issued',
      refreshToken: 'r$_issued',
      expiresIn: const Duration(minutes: 15),
    );
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String locale,
  }) async {
    registerCalls++;
    lastRegisteredLocale = locale;
    if (registerError != null) throw AuthApiException(registerError!);
  }

  @override
  Future<AuthTokens> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    loginCalls++;
    lastDeviceId = deviceId;
    if (loginError != null) throw AuthApiException(loginError!);
    return _nextTokens();
  }

  @override
  Future<AuthTokens> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    refreshCalls++;
    await Future<void>.delayed(Duration.zero);
    if (refreshError != null) throw AuthApiException(refreshError!);
    return _nextTokens();
  }

  @override
  Future<void> logout({required String refreshToken}) async {
    logoutCalls++;
    lastLogoutToken = refreshToken;
  }

  @override
  Future<AuthUser> me(String accessToken) async => user;
}
