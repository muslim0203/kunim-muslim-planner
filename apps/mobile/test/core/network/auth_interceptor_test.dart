import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/network/auth_interceptor.dart';

/// Answers 200 only to `Bearer fresh`, 401 otherwise, and records the
/// Authorization header of every request.
class _Server implements HttpClientAdapter {
  final List<String?> authorizations = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authorization = options.headers['Authorization'] as String?;
    authorizations.add(authorization);
    final ok = authorization == 'Bearer fresh';
    return ResponseBody.fromString(
      ok ? '{"ok":true}' : '{"error":{"code":"http_401"}}',
      ok ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Server server;
  late int refreshes;

  Dio client({String? Function()? renewed}) {
    server = _Server();
    refreshes = 0;
    final options = BaseOptions(baseUrl: 'https://api.test');
    final replay = Dio(options)..httpClientAdapter = server;
    final dio = Dio(options)..httpClientAdapter = server;
    dio.interceptors.add(
      AuthInterceptor(
        accessToken: ({bool forceRefresh = false}) async {
          if (!forceRefresh) return 'stale';
          refreshes++;
          return renewed == null ? 'fresh' : renewed();
        },
        replay: replay,
      ),
    );
    return dio;
  }

  test('a 401 renews the token once and replays the request', () async {
    final dio = client();

    final response = await dio.get<Map<String, dynamic>>('/sync/limits');

    expect(response.statusCode, 200);
    expect(response.data, {'ok': true});
    expect(server.authorizations, ['Bearer stale', 'Bearer fresh']);
    expect(refreshes, 1);
  });

  test('without a renewed token the 401 is passed on', () async {
    final dio = client(renewed: () => null);

    await expectLater(
      dio.get<Object?>('/sync/pull'),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
    expect(server.authorizations, ['Bearer stale']);
  });

  test('auth endpoints get no token and are never replayed', () async {
    final dio = client();

    await expectLater(
      dio.post<Object?>('/auth/login', data: {'email': 'a@b.co'}),
      throwsA(isA<DioException>()),
    );
    expect(server.authorizations, [null]);
    expect(refreshes, 0);
  });
}
