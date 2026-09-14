import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_controller.dart';
import 'auth_interceptor.dart';

/// The deployed API (Railway, production). Override at build time for
/// another server, e.g. a local one:
///   flutter run --dart-define=KUNIM_API_BASE_URL=http://10.0.2.2:8000
const String kunimApiBaseUrl = String.fromEnvironment(
  'KUNIM_API_BASE_URL',
  defaultValue: 'https://api-production-33c6.up.railway.app',
);

/// Base URL for `apps/api`.
final baseUrlProvider = Provider<String>((ref) => kunimApiBaseUrl);

const _requestIdHeader = 'X-Request-Id';
const _uuid = Uuid();

/// Shared [Dio] instance for authenticated API calls (sync, profile, ...).
/// `/auth/*` calls use their own client (`core/auth/auth_api.dart`).
final dioProvider = Provider<Dio>((ref) {
  final options = BaseOptions(
    baseUrl: ref.watch(baseUrlProvider),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 15),
    contentType: 'application/json',
    responseType: ResponseType.json,
  );
  final dio = Dio(options);

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers[_requestIdHeader] = _uuid.v4();
        handler.next(options);
      },
    ),
  );

  // Before the retry interceptor: a 401 is answered by one token refresh and
  // one replay here, and the retry interceptor never retries a 401 itself.
  dio.interceptors.add(
    AuthInterceptor(
      accessToken: ({bool forceRefresh = false}) => ref
          .read(authControllerProvider.notifier)
          .accessToken(forceRefresh: forceRefresh),
      replay: Dio(options),
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
