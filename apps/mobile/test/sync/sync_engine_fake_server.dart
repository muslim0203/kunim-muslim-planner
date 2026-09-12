// A fake `/sync/*` server implemented in plain Dart (ADR-0002 §3) for
// `sync_engine_*_test.dart` — no real HTTP, no real backend. It plays only
// the minimal role the client actually depends on: row-level
// last-write-wins by `updated_at` (matrix rules 1-4), the
// `updated_at_in_future` rejection (rule 6), and cursor-paginated pull with
// an injectable tombstone-purge watermark for `full_resync_required`
// (§4). It intentionally does NOT reimplement the natural-key/additive
// merge rules (9-16) — those are exhaustively covered by
// `apps/api/tests/sync/test_merge_matrix.py` against the real
// `merge.py`, and `conflict.dart` never re-implements them either.
import 'package:kunim/core/sync/conflict.dart' show toRfc3339Millis;
import 'package:kunim/core/sync/sync_api.dart';
import 'package:kunim/core/sync/sync_models.dart';

class FakeSyncServer implements SyncApi {
  FakeSyncServer({
    this.maxChangesPerBatch = 200,
    this.maxPullLimit = 500,
    this.futureToleranceHours = 24,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final int maxChangesPerBatch;
  final int maxPullLimit;
  final int futureToleranceHours;
  final DateTime Function() _now;

  int _versionCounter = 0;
  int? _purgedUpToVersion;

  /// How many times [push] has been called. A permanently-failing outbox must
  /// not make the engine loop for ever, so tests assert a bound on this.
  int pushCallCount = 0;

  /// `entity:rowId` -> the row's current authoritative state (snake_case,
  /// always carries `server_version`).
  final Map<String, Map<String, dynamic>> _rows = {};

  /// Append-only log of every version ever produced, for cursor-based
  /// pull pagination (mirrors the server's real `server_version` pull
  /// query: "rows with server_version > cursor, oldest first").
  final List<SyncPullRow> _log = [];

  int get currentMaxVersion => _versionCounter;

  /// Test hook simulating ADR-0002 §4: any pull with `0 < cursor <
  /// upToVersion` now answers `full_resync_required: true` with empty
  /// rows, exactly like a cursor that fell behind the server's tombstone
  /// purge watermark. `cursor == 0` is exempt, matching the real server's
  /// "a fresh device is always valid" rule — without that exemption the
  /// client's mandated `cursor = 0` recovery pull would loop forever.
  void simulatePurgeBeyond(int upToVersion) {
    _purgedUpToVersion = upToVersion;
  }

  /// Seeds a row directly into server state (bypassing push/merge) for
  /// tests that only need pull-side fixtures, e.g. pagination. [row] must
  /// already be a full, valid snake_case row for [entity] (whatever that
  /// entity's local Drift table requires).
  int seedServerRow(String entity, Map<String, dynamic> row) {
    final version = ++_versionCounter;
    final full = Map<String, dynamic>.from(row)..['server_version'] = version;
    _rows['$entity:${row['id']}'] = full;
    _log.add(SyncPullRow(entity: entity, serverVersion: version, row: full));
    return version;
  }

  @override
  Future<SyncLimits> fetchLimits() async {
    return SyncLimits(
      maxChangesPerBatch: maxChangesPerBatch,
      maxPayloadBytes: 64 * 1024,
      maxBodyBytes: 4 * 1024 * 1024,
      maxPullLimit: maxPullLimit,
      defaultPullLimit: maxPullLimit,
      tombstoneRetentionDays: 90,
      rowHistoryRetentionDays: 30,
      batchRetentionDays: 7,
      futureToleranceHours: futureToleranceHours,
      rejectedReasons: const [
        'updated_at_in_future',
        'schema_invalid',
        'unknown_entity',
        'readonly_entity',
        'foreign_user',
        'payload_too_large',
      ],
      entities: const [],
    );
  }

  @override
  Future<SyncPushResponse> push(SyncPushRequest request) async {
    pushCallCount++;
    if (request.changes.length > maxChangesPerBatch) {
      // A real server would answer HTTP 400 `batch_too_large`; failing
      // loudly here catches an engine that ignores the server-reported
      // cap in favour of a hardcoded constant.
      throw StateError(
        'push batch of ${request.changes.length} exceeds the '
        'server-reported limit of $maxChangesPerBatch',
      );
    }
    final results = request.changes.map(_applyChange).toList(growable: false);
    return SyncPushResponse(
      batchId: request.batchId,
      serverTime: _now(),
      maxServerVersion: _versionCounter,
      results: results,
    );
  }

  SyncPushResult _applyChange(SyncChange change) {
    final key = '${change.entity}:${change.rowId}';
    final incoming = Map<String, dynamic>.from(change.payload);
    final updatedAtRaw = incoming['updated_at'] as String?;
    if (updatedAtRaw == null) {
      return SyncPushResult.rejected(
        clientSeq: change.clientSeq,
        entity: change.entity,
        rowId: change.rowId,
        reason: 'schema_invalid',
      );
    }

    final updatedAt = DateTime.parse(updatedAtRaw);
    final now = _now();
    if (updatedAt.isAfter(now.add(Duration(hours: futureToleranceHours)))) {
      return SyncPushResult.rejected(
        clientSeq: change.clientSeq,
        entity: change.entity,
        rowId: change.rowId,
        reason: 'updated_at_in_future',
      );
    }

    final existing = _rows[key];
    final existingUpdatedAt = existing == null
        ? null
        : DateTime.parse(existing['updated_at'] as String);

    if (existing == null || updatedAt.isAfter(existingUpdatedAt!)) {
      final version = ++_versionCounter;
      final row = Map<String, dynamic>.from(incoming)
        ..['server_version'] = version;
      _rows[key] = row;
      _log.add(
        SyncPullRow(entity: change.entity, serverVersion: version, row: row),
      );
      return SyncPushResult.applied(
        clientSeq: change.clientSeq,
        entity: change.entity,
        rowId: change.rowId,
        serverVersion: version,
      );
    }

    // Rules 2-4: equal-or-earlier `updated_at` means the server's stored
    // state wins (a real merge would collapse an identical payload into a
    // no-op `applied`; folding that into `conflict` here is harmless since
    // `conflict.dart` applies `server_row` unconditionally either way).
    return SyncPushResult.conflict(
      clientSeq: change.clientSeq,
      entity: change.entity,
      rowId: change.rowId,
      serverVersion: existing['server_version'] as int,
      serverRow: existing,
    );
  }

  @override
  Future<SyncPullResponse> pull({
    required int cursor,
    required int limit,
    List<String>? entities,
  }) async {
    final purged = _purgedUpToVersion;
    if (cursor > 0 && purged != null && cursor < purged) {
      return SyncPullResponse(
        rows: const [],
        nextCursor: cursor,
        hasMore: false,
        fullResyncRequired: true,
        serverTime: _now(),
      );
    }

    final effectiveLimit = limit > maxPullLimit ? maxPullLimit : limit;
    var matching = _log.where((r) => r.serverVersion > cursor);
    if (entities != null && entities.isNotEmpty) {
      matching = matching.where((r) => entities.contains(r.entity));
    }
    final all = matching.toList()
      ..sort((a, b) => a.serverVersion.compareTo(b.serverVersion));
    final page = all.take(effectiveLimit).toList(growable: false);
    final nextCursor = page.isEmpty ? cursor : page.last.serverVersion;

    return SyncPullResponse(
      rows: page,
      nextCursor: nextCursor,
      hasMore: all.length > page.length,
      fullResyncRequired: false,
      serverTime: _now(),
    );
  }
}

/// Builds a full, valid snake-case `tasks` row (every column the local
/// `Tasks` Drift table requires) for use as outbox payload / seeded server
/// state. All timestamps are formatted exactly like the wire (RFC 3339,
/// millisecond UTC).
Map<String, dynamic> buildTaskRow({
  required String id,
  required String title,
  DateTime? updatedAt,
  DateTime? createdAt,
  DateTime? deletedAt,
  int serverVersion = 0,
}) {
  final now = updatedAt ?? DateTime.now().toUtc();
  return {
    'id': id,
    'user_id': null,
    'created_at': toRfc3339Millis(createdAt ?? now),
    'updated_at': toRfc3339Millis(now),
    'deleted_at': deletedAt == null ? null : toRfc3339Millis(deletedAt),
    'server_version': serverVersion,
    'title': title,
    'description': null,
    'category_id': null,
    'priority': 1,
    'due_date': null,
    'completed_at': null,
  };
}
