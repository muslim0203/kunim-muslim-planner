import 'package:kunim/core/auth/auth_api.dart';
import 'package:kunim/core/auth/google_sign_in_client.dart';
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
  AuthErrorKind? googleError;
  AuthErrorKind? refreshError;
  AuthErrorKind? deleteError;
  AuthErrorKind? forgotError;
  AuthErrorKind? resetError;

  int registerCalls = 0;
  int loginCalls = 0;
  int googleCalls = 0;
  String? lastGoogleIdToken;
  String? lastGoogleLocale;
  String? lastDeleteGoogleIdToken;
  int refreshCalls = 0;
  int logoutCalls = 0;
  int deleteCalls = 0;
  String? lastDeviceId;
  String? lastLogoutToken;
  String? lastRegisteredLocale;
  String? lastDeleteAccessToken;
  String? lastDeletePassword;
  String? lastForgotEmail;
  String? lastForgotLocale;
  String? lastResetEmail;
  String? lastResetCode;
  String? lastResetPassword;
  int forgotCalls = 0;
  int resetCalls = 0;

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
  Future<AuthTokens> googleSignIn({
    required String idToken,
    required String deviceId,
    required String locale,
  }) async {
    googleCalls++;
    lastGoogleIdToken = idToken;
    lastGoogleLocale = locale;
    lastDeviceId = deviceId;
    if (googleError != null) throw AuthApiException(googleError!);
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

  @override
  Future<void> deleteAccount({
    required String accessToken,
    String? password,
    String? googleIdToken,
  }) async {
    deleteCalls++;
    lastDeleteAccessToken = accessToken;
    lastDeletePassword = password;
    lastDeleteGoogleIdToken = googleIdToken;
    if (deleteError != null) throw AuthApiException(deleteError!);
  }

  @override
  Future<void> requestPasswordReset({
    required String email,
    required String locale,
  }) async {
    forgotCalls++;
    lastForgotEmail = email;
    lastForgotLocale = locale;
    if (forgotError != null) throw AuthApiException(forgotError!);
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    resetCalls++;
    lastResetEmail = email;
    lastResetCode = code;
    lastResetPassword = newPassword;
    if (resetError != null) throw AuthApiException(resetError!);
  }
}

/// Hands out [token] or fails with [failure]; counts sign-outs.
class FakeGoogleSignInClient implements GoogleSignInClient {
  FakeGoogleSignInClient({this.token = 'google-id-token', this.failure});

  @override
  bool isAvailable = true;

  String token;
  GoogleSignInFailure? failure;
  int idTokenCalls = 0;
  int signOutCalls = 0;

  @override
  Future<String> idToken() async {
    idTokenCalls++;
    if (failure != null) throw GoogleSignInClientException(failure!);
    return token;
  }

  @override
  Future<void> signOut() async => signOutCalls++;
}
