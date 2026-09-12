// Transport-failure handling: a `SyncApi` that always throws must produce
// a `SyncFailed` status with exponential backoff (not a silent infinite
// retry loop), and `persistentlyFailing` must flip on once 10 consecutive
// cycles have failed — "surface a change after 10 failed attempts rather
// than retrying forever".
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/network/error_mapper.dart';
import 'package:kunim/core/sync/outbox.dart';
import 'package:kunim/core/sync/sync_api.dart';
import 'package:kunim/core/sync/sync_engine.dart';
import 'package:kunim/core/sync/sync_models.dart';

class _AlwaysOfflineApi implements SyncApi {
  int calls = 0;

  @override
  Future<SyncLimits> fetchLimits() async => SyncLimits.fallback;

  @override
  Future<SyncPullResponse> pull({
    required int cursor,
    required int limit,
    List<String>? entities,
  }) async {
    calls++;
    throw const SyncApiException(NetworkFailure(message: 'offline'));
  }

  @override
  Future<SyncPushResponse> push(SyncPushRequest request) async {
    calls++;
    throw const SyncApiException(NetworkFailure(message: 'offline'));
  }
}

void main() {
  late AppDatabase db;
  late _AlwaysOfflineApi api;
  late SyncEngine engine;
  var fakeNow = DateTime.utc(2026, 9, 12);

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    api = _AlwaysOfflineApi();
    fakeNow = DateTime.utc(2026, 9, 12);
    engine = SyncEngine(
      db: db,
      api: api,
      outboxDao: OutboxDao(db),
      stateStore: SyncStateStore(db),
      now: () => fakeNow,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('a transport failure yields SyncFailed with an increasing backoff',
      () async {
    final first = await engine.syncOnce(force: true) as SyncFailed;
    expect(first.consecutiveFailures, 1);
    expect(first.persistentlyFailing, isFalse);

    // Immediately trying again without forcing must be skipped: still
    // inside the 1s backoff window from the first failure.
    final skipped = await engine.syncOnce();
    expect(skipped, isA<SyncSkippedBackoff>());
    expect(api.calls, 1, reason: 'a backed-off cycle must not call the API');

    // Advance the clock past the backoff window and try again.
    fakeNow = fakeNow.add(const Duration(seconds: 2));
    final second = await engine.syncOnce() as SyncFailed;
    expect(second.consecutiveFailures, 2);
    expect(api.calls, 2);
  });

  test('persistentlyFailing flips on at the 10th consecutive failure',
      () async {
    SyncStatus? last;
    for (var i = 0; i < 10; i++) {
      last = await engine.syncOnce(force: true);
      fakeNow = fakeNow.add(const Duration(minutes: 20));
    }
    final failed = last as SyncFailed;
    expect(failed.consecutiveFailures, 10);
    expect(failed.persistentlyFailing, isTrue);
  });

  test('a manual (forced) sync ignores the backoff window', () async {
    await engine.syncOnce(force: true);
    final forced = await engine.syncOnce(force: true);
    expect(forced, isA<SyncFailed>());
    expect(api.calls, 2);
  });
}
