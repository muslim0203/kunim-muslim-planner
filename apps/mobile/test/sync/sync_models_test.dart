// JSON round-trip tests for the ADR-0002 §3 wire models. Field names must
// match the ADR's examples EXACTLY (`client_seq`, `row_id`, `base_version`,
// `device_id`, `batch_id`, `server_time`, `max_server_version`, `status`,
// `server_version`, `server_row`, `reason`, `next_cursor`, `has_more`,
// `full_resync_required`) since the server half of this contract is built
// against the same document by a separate agent.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/sync/sync_models.dart';

void main() {
  group('SyncChange', () {
    test('round-trips and uses the ADR field names', () {
      final change = SyncChange(
        clientSeq: 128,
        entity: 'tasks',
        rowId: '6b1d0000-0000-4000-8000-000000000000',
        op: SyncOp.upsert,
        baseVersion: 41,
        payload: const {
          'id': '6b1d0000-0000-4000-8000-000000000000',
          'updated_at': '2026-09-12T08:30:00.000Z',
        },
      );

      final json = change.toJson();
      expect(json['client_seq'], 128);
      expect(json['row_id'], '6b1d0000-0000-4000-8000-000000000000');
      expect(json['op'], 'upsert');
      expect(json['base_version'], 41);
      expect(json.containsKey('clientSeq'), isFalse);

      final decoded = SyncChange.fromJson(json);
      expect(decoded, change);
    });

    test('op serializes to the exact "upsert"/"delete" wire literals', () {
      expect(
        SyncChange(
          clientSeq: 1,
          entity: 'tasks',
          rowId: 'r',
          op: SyncOp.delete,
          baseVersion: 0,
          payload: const {},
        ).toJson()['op'],
        'delete',
      );
    });
  });

  test('SyncPushRequest round-trips a batch of changes', () {
    final request = SyncPushRequest(
      deviceId: '9f0e0000-0000-4000-8000-000000000000',
      batchId: '1c1f0000-0000-4000-8000-000000000000',
      changes: [
        SyncChange(
          clientSeq: 128,
          entity: 'tasks',
          rowId: '6b1d',
          op: SyncOp.upsert,
          baseVersion: 41,
          payload: const {'id': '6b1d'},
        ),
      ],
    );

    final json = request.toJson();
    expect(json['device_id'], '9f0e0000-0000-4000-8000-000000000000');
    expect(json['batch_id'], '1c1f0000-0000-4000-8000-000000000000');
    expect(json['changes'], isA<List<dynamic>>());

    expect(SyncPushRequest.fromJson(json), request);
  });

  group('SyncPushResult', () {
    test('applied round-trips with status discriminator', () {
      const result = SyncPushResult.applied(
        clientSeq: 128,
        entity: 'tasks',
        rowId: '6b1d',
        serverVersion: 10427,
      );

      final json = result.toJson();
      expect(json['status'], 'applied');
      expect(json['server_version'], 10427);
      expect(SyncPushResult.fromJson(json), result);
    });

    test('conflict round-trips including the full server_row', () {
      final result = SyncPushResult.conflict(
        clientSeq: 129,
        entity: 'habit_logs',
        rowId: '77aa',
        serverVersion: 10428,
        serverRow: const {'id': '77aa', 'count': 3},
      );

      final json = result.toJson();
      expect(json['status'], 'conflict');
      expect(json['server_row'], {'id': '77aa', 'count': 3});
      expect(SyncPushResult.fromJson(json), result);
    });

    test('rejected round-trips with a reason', () {
      const result = SyncPushResult.rejected(
        clientSeq: 130,
        entity: 'tasks',
        rowId: '88bb',
        reason: 'updated_at_in_future',
      );

      final json = result.toJson();
      expect(json['status'], 'rejected');
      expect(json['reason'], 'updated_at_in_future');
      expect(SyncPushResult.fromJson(json), result);
    });

    test('matches the ADR-0002 §3 example response body verbatim', () {
      // Straight from the ADR's "// Response 200" example under
      // `POST /sync/push`.
      final results = [
        {
          'client_seq': 128,
          'row_id': '6b1d...',
          'entity': 'tasks',
          'status': 'applied',
          'server_version': 10427,
        },
        {
          'client_seq': 129,
          'row_id': '77aa...',
          'entity': 'habit_logs',
          'status': 'conflict',
          'server_version': 10428,
          'server_row': {'...': '...'},
        },
        {
          'client_seq': 130,
          'row_id': '88bb...',
          'entity': 'tasks',
          'status': 'rejected',
          'reason': 'updated_at_in_future',
        },
      ];

      final parsed = results.map(SyncPushResult.fromJson).toList();
      expect(parsed[0], isA<SyncPushResultApplied>());
      expect(parsed[1], isA<SyncPushResultConflict>());
      expect(parsed[2], isA<SyncPushResultRejected>());
    });
  });

  test('SyncPushResponse round-trips the full envelope', () {
    final response = SyncPushResponse(
      batchId: '1c1f',
      serverTime: DateTime.utc(2026, 9, 12, 8, 30, 1),
      maxServerVersion: 10428,
      results: const [
        SyncPushResult.applied(
          clientSeq: 128,
          entity: 'tasks',
          rowId: '6b1d',
          serverVersion: 10427,
        ),
      ],
    );

    final json = response.toJson();
    expect(json['batch_id'], '1c1f');
    expect(json['max_server_version'], 10428);
    expect(SyncPushResponse.fromJson(json), response);
  });

  test('SyncPullRow round-trips including a tombstone row', () {
    final row = SyncPullRow(
      entity: 'tasks',
      serverVersion: 10430,
      row: const {'id': 'x', 'deleted_at': '2026-09-10T12:00:00.000Z'},
    );

    final json = row.toJson();
    expect(json['server_version'], 10430);
    expect(SyncPullRow.fromJson(json), row);
  });

  group('SyncPullResponse', () {
    test('round-trips next_cursor/has_more/full_resync_required', () {
      final response = SyncPullResponse(
        rows: [
          SyncPullRow(
            entity: 'tasks',
            serverVersion: 10427,
            row: const {'id': 'a', 'deleted_at': null},
          ),
        ],
        nextCursor: 10430,
        hasMore: false,
        fullResyncRequired: false,
        serverTime: DateTime.utc(2026, 9, 12, 8, 30, 1),
      );

      final json = response.toJson();
      expect(json['next_cursor'], 10430);
      expect(json['has_more'], false);
      expect(json['full_resync_required'], false);
      expect(SyncPullResponse.fromJson(json), response);
    });

    test('full_resync_required with empty rows round-trips', () {
      final response = SyncPullResponse(
        rows: const [],
        nextCursor: 0,
        hasMore: false,
        fullResyncRequired: true,
        serverTime: DateTime.utc(2026, 9, 12, 8, 30, 1),
      );

      final json = response.toJson();
      expect(json['rows'], isEmpty);
      expect(json['full_resync_required'], true);
      expect(SyncPullResponse.fromJson(json), response);
    });
  });
}
