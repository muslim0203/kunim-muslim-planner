/// The API's `/social/*` endpoints and the two profile fields a board needs
/// (`PATCH /users/me`).
///
/// Uses the shared authenticated client (`core/network/api_client.dart`), so
/// the access token is attached and renewed for these calls like any other.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/board.dart';

enum SocialErrorKind {
  /// No invite with that code.
  codeNotFound,

  /// The code was already used, or it has expired.
  codeSpent,

  /// The user tried to redeem their own code.
  ownCode,

  /// The nickname is already taken by someone else.
  nicknameTaken,

  /// The global board needs a nickname first.
  nicknameRequired,
  network,
  server,
}

class SocialApiException implements Exception {
  const SocialApiException(this.kind);

  final SocialErrorKind kind;

  @override
  String toString() => 'SocialApiException($kind)';
}

abstract interface class SocialApi {
  Future<InviteCode> createInvite();

  Future<void> acceptInvite(String code);

  Future<Board> friendsBoard();

  Future<Board> globalBoard();

  Future<void> removeFriend(String userId);

  /// Sets the name shown on a board and whether to appear on the global one.
  Future<void> updateBoardProfile({String? nickname, bool? leaderboardOptIn});
}

class DioSocialApi implements SocialApi {
  const DioSocialApi(this._dio);

  final Dio _dio;

  @override
  Future<InviteCode> createInvite() async {
    final data = await _send(
      () => _dio.post<Map<String, dynamic>>('/social/invites'),
    );
    return InviteCode.fromJson(data!);
  }

  @override
  Future<void> acceptInvite(String code) async {
    await _send(
      () => _dio.post<Object?>(
        '/social/invites/accept',
        data: {'code': code},
      ),
    );
  }

  @override
  Future<Board> friendsBoard() async {
    final data = await _send(
      () => _dio.get<Map<String, dynamic>>('/social/friends'),
    );
    return Board.fromJson(data!);
  }

  @override
  Future<Board> globalBoard() async {
    final data = await _send(
      () => _dio.get<Map<String, dynamic>>('/social/leaderboard'),
    );
    return Board.fromJson(data!);
  }

  @override
  Future<void> removeFriend(String userId) async {
    await _send(() => _dio.delete<Object?>('/social/friends/$userId'));
  }

  @override
  Future<void> updateBoardProfile({
    String? nickname,
    bool? leaderboardOptIn,
  }) async {
    await _send(
      () => _dio.patch<Map<String, dynamic>>(
        '/users/me',
        data: {
          if (nickname != null) 'nickname': nickname,
          if (leaderboardOptIn != null) 'leaderboard_opt_in': leaderboardOptIn,
        },
      ),
    );
  }

  static Future<T?> _send<T>(Future<Response<T>> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (error) {
      throw SocialApiException(_kindOf(error));
    }
  }

  static SocialErrorKind _kindOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return SocialErrorKind.network;
    }
    return switch (error.response?.statusCode ?? 0) {
      404 => SocialErrorKind.codeNotFound,
      410 => SocialErrorKind.codeSpent,
      409 => SocialErrorKind.nicknameTaken,
      // The server answers 400 for a code that is the caller's own and for a
      // leaderboard opt-in without a nickname; the two never share a call.
      400 => SocialErrorKind.ownCode,
      _ => SocialErrorKind.server,
    };
  }
}

final socialApiProvider = Provider<SocialApi>((ref) {
  return DioSocialApi(ref.watch(dioProvider));
});
