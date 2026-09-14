import 'package:dio/dio.dart';

/// Attaches the account's access token to API calls and, when the server
/// still answers 401, renews the token once and replays the request once.
///
/// `/auth/*` and `/health` are left alone. A [QueuedInterceptor], so
/// concurrent 401s wait for one another instead of each refreshing.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({required this.accessToken, required this.replay});

  /// Returns a usable access token (`null` when there is none).
  final Future<String?> Function({bool forceRefresh}) accessToken;

  /// Client the retried request is sent with. It must not carry this
  /// interceptor, so a second 401 is final.
  final Dio replay;

  static const String _retriedKey = 'kunim.auth.retried';

  static bool _isPublic(RequestOptions options) =>
      options.path.startsWith('/auth/') || options.path.startsWith('/health');

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isPublic(options)) {
      final token = await accessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 ||
        _isPublic(options) ||
        options.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }
    final token = await accessToken(forceRefresh: true);
    if (token == null) {
      handler.next(err);
      return;
    }
    options.headers['Authorization'] = 'Bearer $token';
    options.extra[_retriedKey] = true;
    try {
      handler.resolve(await replay.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
