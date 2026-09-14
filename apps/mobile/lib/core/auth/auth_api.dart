/// The API's `/auth/*` endpoints (`apps/api/app/modules/auth/router.py`).
///
/// Uses its own [Dio] ([authDioProvider]) without the shared client's retry
/// or auth interceptors: a refresh token is valid exactly once, so a retried
/// `/auth/refresh` whose first response was lost would present a rotated
/// token, which the server treats as reuse and answers by revoking the
/// session.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: Duration(seconds: (json['expires_in'] as num).toInt()),
    );
  }

  final String accessToken;
  final String refreshToken;

  /// Lifetime of [accessToken].
  final Duration expiresIn;
}

class AuthUser {
  const AuthUser({required this.id, required this.email});

  final String id;
  final String email;
}

enum AuthErrorKind {
  /// Wrong email/password, or a refresh token the server no longer accepts.
  invalidCredentials,
  invalidInput,
  rateLimited,
  network,
  server,
}

class AuthApiException implements Exception {
  const AuthApiException(this.kind);

  final AuthErrorKind kind;

  @override
  String toString() => 'AuthApiException($kind)';
}

abstract interface class AuthApi {
  /// Creates an account. The server answers the same way whether or not the
  /// email is already taken, so success is confirmed by signing in.
  Future<void> register({
    required String email,
    required String password,
    required String locale,
  });

  Future<AuthTokens> login({
    required String email,
    required String password,
    required String deviceId,
  });

  Future<AuthTokens> refresh({
    required String refreshToken,
    required String deviceId,
  });

  Future<void> logout({required String refreshToken});

  Future<AuthUser> me(String accessToken);
}

class DioAuthApi implements AuthApi {
  const DioAuthApi(this._dio);

  final Dio _dio;

  @override
  Future<void> register({
    required String email,
    required String password,
    required String locale,
  }) async {
    await _send(
      () => _dio.post<Object?>(
        '/auth/register',
        data: {'email': email, 'password': password, 'locale': locale},
      ),
    );
  }

  @override
  Future<AuthTokens> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    final data = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password, 'device_id': deviceId},
      ),
    );
    return AuthTokens.fromJson(data!);
  }

  @override
  Future<AuthTokens> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    final data = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken, 'device_id': deviceId},
      ),
    );
    return AuthTokens.fromJson(data!);
  }

  @override
  Future<void> logout({required String refreshToken}) async {
    await _send(
      () => _dio.post<Object?>(
        '/auth/logout',
        data: {'refresh_token': refreshToken},
      ),
    );
  }

  @override
  Future<AuthUser> me(String accessToken) async {
    final data = await _send(
      () => _dio.get<Map<String, dynamic>>(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      ),
    );
    return AuthUser(id: data!['id'] as String, email: data['email'] as String);
  }

  static Future<T?> _send<T>(Future<Response<T>> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (error) {
      throw AuthApiException(_kindOf(error));
    }
  }

  static AuthErrorKind _kindOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return AuthErrorKind.network;
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 401 || status == 403) return AuthErrorKind.invalidCredentials;
    if (status == 429) return AuthErrorKind.rateLimited;
    if (status >= 400 && status < 500) return AuthErrorKind.invalidInput;
    return AuthErrorKind.server;
  }
}

/// Plain client for `/auth/*`: no retry, no token interceptor (see the
/// library comment).
final authDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: ref.watch(baseUrlProvider),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
      responseType: ResponseType.json,
    ),
  );
});

final authApiProvider = Provider<AuthApi>((ref) {
  return DioAuthApi(ref.watch(authDioProvider));
});
