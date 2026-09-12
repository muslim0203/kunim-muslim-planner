/// Thin HTTP wrapper over the three `/sync/*` endpoints defined by
/// `docs/adr/0002-sync.md` §3 and implemented server-side in
/// `apps/api/app/modules/sync/{router,schemas}.py`.
///
/// This file performs NO retry/backoff/mutex policy and NO merge logic — it
/// only shapes requests, parses responses, and maps transport failures to
/// [ApiFailure] via the existing `core/network/error_mapper.dart`. Cycle
/// orchestration (draining the outbox, paginating pulls, single-flight,
/// backoff) lives in `sync_engine.dart`.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../network/error_mapper.dart';
import 'sync_models.dart';

/// Wraps an [ApiFailure] so `sync_engine.dart` can catch a single exception
/// type from any [SyncApi] call and inspect the sealed [failure] for retry
/// decisions, without depending on `dio` directly.
class SyncApiException implements Exception {
  const SyncApiException(this.failure);

  final ApiFailure failure;

  @override
  String toString() => 'SyncApiException(${failure.runtimeType})';
}

/// One entry of `LimitsResponse.entities` (`apps/api/app/modules/sync/
/// schemas.py#EntityLimits`) — informational metadata about a registered
/// sync entity, not itself a cap.
class SyncEntityInfo {
  const SyncEntityInfo({
    required this.name,
    required this.direction,
    required this.naturalKey,
    required this.adrRules,
  });

  final String name;
  final String direction;
  final List<String> naturalKey;
  final List<int> adrRules;

  factory SyncEntityInfo.fromJson(Map<String, dynamic> json) {
    return SyncEntityInfo(
      name: json['name'] as String,
      direction: json['direction'] as String,
      naturalKey: (json['natural_key'] as List<dynamic>).cast<String>(),
      adrRules: (json['adr_rules'] as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toList(growable: false),
    );
  }
}

/// `GET /sync/limits` response (ADR-0002 §3 rule 5): batch/payload caps and
/// the closed `rejected_reasons` enum, read from the server rather than
/// hardcoded on the client. Field names/defaults mirror
/// `apps/api/app/modules/sync/schemas.py#LimitsResponse` exactly.
class SyncLimits {
  const SyncLimits({
    required this.maxChangesPerBatch,
    required this.maxPayloadBytes,
    required this.maxBodyBytes,
    required this.maxPullLimit,
    required this.defaultPullLimit,
    required this.tombstoneRetentionDays,
    required this.rowHistoryRetentionDays,
    required this.batchRetentionDays,
    required this.futureToleranceHours,
    required this.rejectedReasons,
    required this.entities,
  });

  final int maxChangesPerBatch;
  final int maxPayloadBytes;
  final int maxBodyBytes;
  final int maxPullLimit;
  final int defaultPullLimit;
  final int tombstoneRetentionDays;
  final int rowHistoryRetentionDays;
  final int batchRetentionDays;
  final int futureToleranceHours;
  final List<String> rejectedReasons;
  final List<SyncEntityInfo> entities;

  /// Conservative last-resort fallback matching the ADR's own defaults
  /// (`apps/api/app/modules/sync/schemas.py` constants), used only when
  /// `GET /sync/limits` has never once succeeded — the server remains the
  /// source of truth whenever reachable (ADR rule 5).
  static const fallback = SyncLimits(
    maxChangesPerBatch: 200,
    maxPayloadBytes: 64 * 1024,
    maxBodyBytes: 4 * 1024 * 1024,
    maxPullLimit: 500,
    defaultPullLimit: 500,
    tombstoneRetentionDays: 90,
    rowHistoryRetentionDays: 30,
    batchRetentionDays: 7,
    futureToleranceHours: 24,
    rejectedReasons: [
      'updated_at_in_future',
      'schema_invalid',
      'unknown_entity',
      'readonly_entity',
      'foreign_user',
      'payload_too_large',
    ],
    entities: [],
  );

  factory SyncLimits.fromJson(Map<String, dynamic> json) {
    return SyncLimits(
      maxChangesPerBatch: json['max_changes_per_batch'] as int,
      maxPayloadBytes: json['max_payload_bytes'] as int,
      maxBodyBytes: json['max_body_bytes'] as int,
      maxPullLimit: json['max_pull_limit'] as int,
      defaultPullLimit: json['default_pull_limit'] as int,
      tombstoneRetentionDays: json['tombstone_retention_days'] as int,
      rowHistoryRetentionDays: json['row_history_retention_days'] as int,
      batchRetentionDays: json['batch_retention_days'] as int,
      futureToleranceHours: json['future_tolerance_hours'] as int,
      rejectedReasons:
          (json['rejected_reasons'] as List<dynamic>).cast<String>(),
      entities: (json['entities'] as List<dynamic>)
          .map((e) => SyncEntityInfo.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// Everything the sync engine needs from the network, as an interface so
/// tests can substitute an in-memory fake sync server (no real HTTP, no
/// real server) instead of a [Dio] instance. See
/// `test/sync/sync_engine_fake_server.dart`.
abstract interface class SyncApi {
  Future<SyncLimits> fetchLimits();

  Future<SyncPushResponse> push(SyncPushRequest request);

  Future<SyncPullResponse> pull({
    required int cursor,
    required int limit,
    List<String>? entities,
  });
}

/// Production [SyncApi] backed by the shared [Dio] instance
/// (`core/network/api_client.dart`). No auth headers are added here —
/// token attachment/refresh is `core/auth/` (Phase 1); this file only
/// shapes the sync-specific request/response bodies.
class DioSyncApi implements SyncApi {
  const DioSyncApi(this._dio);

  final Dio _dio;

  @override
  Future<SyncLimits> fetchLimits() async {
    final data = await _get('/sync/limits');
    return SyncLimits.fromJson(data);
  }

  @override
  Future<SyncPushResponse> push(SyncPushRequest request) async {
    final data = await _post('/sync/push', request.toJson());
    return SyncPushResponse.fromJson(data);
  }

  @override
  Future<SyncPullResponse> pull({
    required int cursor,
    required int limit,
    List<String>? entities,
  }) async {
    final data = await _get(
      '/sync/pull',
      queryParameters: {
        'cursor': cursor,
        'limit': limit,
        if (entities != null && entities.isNotEmpty)
          'entities': entities.join(','),
      },
    );
    return SyncPullResponse.fromJson(data);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      return response.data!;
    } on DioException catch (e) {
      throw SyncApiException(mapDioExceptionToApiFailure(e));
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
      );
      return response.data!;
    } on DioException catch (e) {
      throw SyncApiException(mapDioExceptionToApiFailure(e));
    }
  }
}

/// Riverpod provider for the production [SyncApi]. Tests should not depend
/// on this — construct a fake [SyncApi] and pass it directly to
/// `SyncEngine` instead of overriding this provider, since the fake server
/// has no [Dio]/HTTP layer to speak of.
final syncApiProvider = Provider<SyncApi>((ref) {
  return DioSyncApi(ref.watch(dioProvider));
});
