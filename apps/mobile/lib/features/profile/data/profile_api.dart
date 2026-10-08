/// Reads and writes the account's own details (`GET`/`PATCH /users/me`).
///
/// Online only, on purpose. The profile is one row the server owns, not a
/// synced entity: there is no offline queue for it, so an edit either reaches
/// the server now or the user is told it did not. That keeps "saved" honest —
/// a name that silently failed to save is worse than an error.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/profile.dart';

enum ProfileErrorKind {
  /// No connection, a timeout, or the server never answered.
  network,

  /// The session is gone; the user has to sign in again.
  unauthorized,

  /// The handle is taken (the server enforces uniqueness).
  nicknameTaken,

  /// The server rejected a value — a height outside the plausible range, a
  /// handle with characters it does not allow.
  invalid,
}

class ProfileApiException implements Exception {
  const ProfileApiException(this.kind);

  final ProfileErrorKind kind;

  @override
  String toString() => 'ProfileApiException($kind)';
}

class ProfileApi {
  const ProfileApi(this._dio);

  final Dio _dio;

  Future<Profile> fetch() async {
    final data = await _send(() => _dio.get<Map<String, dynamic>>('/users/me'));
    return Profile.fromJson(data!);
  }

  /// Sends only the fields the caller actually wants changed.
  ///
  /// `clear*` flags exist because `null` already means "leave alone" here:
  /// without them there would be no way to empty a field the user had filled
  /// in before.
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
    final body = <String, dynamic>{
      if (clearDisplayName) 'display_name': null,
      if (!clearDisplayName && displayName != null) 'display_name': displayName,
      if (clearNickname) 'nickname': null,
      if (!clearNickname && nickname != null) 'nickname': nickname,
      if (clearBirthYear) 'birth_year': null,
      if (!clearBirthYear && birthYear != null) 'birth_year': birthYear,
      if (clearHeight) 'height_cm': null,
      if (!clearHeight && heightCm != null) 'height_cm': heightCm,
    };

    final data = await _send(
      () => _dio.patch<Map<String, dynamic>>('/users/me', data: body),
    );
    return Profile.fromJson(data!);
  }

  static Future<T?> _send<T>(Future<Response<T>> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (error) {
      throw ProfileApiException(_kindOf(error));
    }
  }

  static ProfileErrorKind _kindOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return ProfileErrorKind.network;
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 401) return ProfileErrorKind.unauthorized;
    if (status == 409) return ProfileErrorKind.nicknameTaken;
    if (status == 422 || status == 400) return ProfileErrorKind.invalid;
    return ProfileErrorKind.network;
  }
}

final profileApiProvider = Provider<ProfileApi>(
  (ref) => ProfileApi(ref.watch(dioProvider)),
);
