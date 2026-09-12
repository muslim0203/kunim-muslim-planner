/// Wire models for the `/sync/push` and `/sync/pull` contract defined by
/// `docs/adr/0002-sync.md`. Field names and JSON keys here are taken
/// verbatim from the ADR's request/response examples — do not rename or
/// reshape them without updating the ADR first, since `apps/api/app/modules
/// /sync/` is built against the same document by a separate agent.
///
/// This file is serialization only. It does NOT perform any networking or
/// merge logic — that is `core/sync/sync_engine.dart` and
/// `core/sync/conflict.dart` (a later task, T-204). ADR-0002 §"Konflikt
/// matritsasi": merge itself lives ONLY on the server; the client accepts
/// `conflict.server_row` unconditionally.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../db/base_repository.dart' show SyncOp;

export '../db/base_repository.dart' show SyncOp;

part 'sync_models.freezed.dart';
part 'sync_models.g.dart';

/// One outbox row as sent to the server in a `POST /sync/push` request
/// (ADR-0002 §3). `payload` is the row's full state, already stripped of
/// the client-only `dirty` column (see `base_repository.dart#syncPayload`).
@freezed
abstract class SyncChange with _$SyncChange {
  const factory SyncChange({
    @JsonKey(name: 'client_seq') required int clientSeq,
    required String entity,
    @JsonKey(name: 'row_id') required String rowId,
    required SyncOp op,
    @JsonKey(name: 'base_version') required int baseVersion,
    required Map<String, dynamic> payload,
  }) = _SyncChange;

  factory SyncChange.fromJson(Map<String, dynamic> json) =>
      _$SyncChangeFromJson(json);
}

/// Request body for `POST /sync/push` (ADR-0002 §3). `changes` must be in
/// outbox `seq` order and capped at the server's push limit (ADR-0002 rule
/// 5: local default 200 until `GET /sync/limits` is wired up).
@freezed
abstract class SyncPushRequest with _$SyncPushRequest {
  const factory SyncPushRequest({
    @JsonKey(name: 'device_id') required String deviceId,
    @JsonKey(name: 'batch_id') required String batchId,
    required List<SyncChange> changes,
  }) = _SyncPushRequest;

  factory SyncPushRequest.fromJson(Map<String, dynamic> json) =>
      _$SyncPushRequestFromJson(json);
}

/// Per-change outcome of a push, discriminated by the `status` JSON field
/// exactly as ADR-0002 §3 defines it — always one of `applied`, `conflict`
/// or `rejected`, never left ambiguous.
@Freezed(unionKey: 'status')
sealed class SyncPushResult with _$SyncPushResult {
  /// The server's state now matches what the client sent.
  const factory SyncPushResult.applied({
    @JsonKey(name: 'client_seq') required int clientSeq,
    required String entity,
    @JsonKey(name: 'row_id') required String rowId,
    @JsonKey(name: 'server_version') required int serverVersion,
  }) = SyncPushResultApplied;

  /// Merge produced a state different from what the client sent; `serverRow`
  /// is the full, authoritative row and must unconditionally replace the
  /// local one (ADR-0002 §3 table + rule 8 of "Amalga oshirish" section).
  const factory SyncPushResult.conflict({
    @JsonKey(name: 'client_seq') required int clientSeq,
    required String entity,
    @JsonKey(name: 'row_id') required String rowId,
    @JsonKey(name: 'server_version') required int serverVersion,
    @JsonKey(name: 'server_row') required Map<String, dynamic> serverRow,
  }) = SyncPushResultConflict;

  /// Not accepted, and will not be accepted as-is. `reason` is one of the
  /// closed enum values in ADR-0002 §3 ("rejected sabablari"):
  /// `updated_at_in_future`, `schema_invalid`, `unknown_entity`,
  /// `readonly_entity`, `foreign_user`, `payload_too_large`. Kept as a
  /// `String` (not a Dart enum) so an unrecognized future reason still
  /// deserializes instead of throwing — the sync engine's `switch` over it
  /// should have a default/fallback branch.
  const factory SyncPushResult.rejected({
    @JsonKey(name: 'client_seq') required int clientSeq,
    required String entity,
    @JsonKey(name: 'row_id') required String rowId,
    required String reason,
  }) = SyncPushResultRejected;

  factory SyncPushResult.fromJson(Map<String, dynamic> json) =>
      _$SyncPushResultFromJson(json);
}

/// Response body for `POST /sync/push` (ADR-0002 §3).
@freezed
abstract class SyncPushResponse with _$SyncPushResponse {
  const factory SyncPushResponse({
    @JsonKey(name: 'batch_id') required String batchId,
    @JsonKey(name: 'server_time') required DateTime serverTime,
    @JsonKey(name: 'max_server_version') required int maxServerVersion,
    required List<SyncPushResult> results,
  }) = _SyncPushResponse;

  factory SyncPushResponse.fromJson(Map<String, dynamic> json) =>
      _$SyncPushResponseFromJson(json);
}

/// One row inside a `GET /sync/pull` response (ADR-0002 §3). `row` is the
/// raw server-side JSON for the entity, including a `deleted_at` tombstone
/// marker when the row was soft-deleted.
@freezed
abstract class SyncPullRow with _$SyncPullRow {
  const factory SyncPullRow({
    required String entity,
    @JsonKey(name: 'server_version') required int serverVersion,
    required Map<String, dynamic> row,
  }) = _SyncPullRow;

  factory SyncPullRow.fromJson(Map<String, dynamic> json) =>
      _$SyncPullRowFromJson(json);
}

/// Response body for `GET /sync/pull` (ADR-0002 §3).
///
/// - [nextCursor]/[hasMore]: the client must only persist [nextCursor]
///   after the whole page has been applied inside one local transaction
///   (ADR-0002 rule 7), then immediately re-request while [hasMore] is
///   true.
/// - [fullResyncRequired]: true means the requested cursor fell outside the
///   server's tombstone-purge window; [rows] is empty and the client MUST
///   run the mandatory 4-step full resync in ADR-0002 §4 rather than a
///   partial catch-up.
@freezed
abstract class SyncPullResponse with _$SyncPullResponse {
  const factory SyncPullResponse({
    required List<SyncPullRow> rows,
    @JsonKey(name: 'next_cursor') required int nextCursor,
    @JsonKey(name: 'has_more') required bool hasMore,
    @JsonKey(name: 'full_resync_required') required bool fullResyncRequired,
    @JsonKey(name: 'server_time') required DateTime serverTime,
  }) = _SyncPullResponse;

  factory SyncPullResponse.fromJson(Map<String, dynamic> json) =>
      _$SyncPullResponseFromJson(json);
}
