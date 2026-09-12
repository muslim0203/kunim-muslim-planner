import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Base URL for `apps/api`. Phase 0 hardcodes a placeholder; Phase 1 should
/// read this from a build-time flavor/environment config instead.
final baseUrlProvider = Provider<String>((ref) {
  return 'https://api.kunim.app';
});

const _requestIdHeader = 'X-Request-Id';
const _uuid = Uuid();

/// Shared [Dio] instance for the whole app. No auth/token-refresh logic
/// here yet — that is added in Phase 1 by `core/network/auth_interceptor.dart`
/// and `core/auth/`.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ref.watch(baseUrlProvider),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
      responseType: ResponseType.json,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers[_requestIdHeader] = _uuid.v4();
        handler.next(options);
      },
    ),
  );

  dio.interceptors.add(
    RetryInterceptor(
      dio: dio,
      retries: 3,
      retryDelays: const [
        Duration(milliseconds: 500),
        Duration(seconds: 1),
        Duration(seconds: 2),
      ],
    ),
  );

  return dio;
});
