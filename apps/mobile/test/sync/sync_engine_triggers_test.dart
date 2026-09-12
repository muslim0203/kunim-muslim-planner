// `SyncTriggerScheduler`'s trigger *policy* (ADR-0002 §2), exercised
// directly against its `on...` methods so it is testable without a real
// device, timer, or connectivity plugin: app resume, connectivity
// restored (only on the none -> connected transition), after N local
// writes, and pull-to-refresh (always forced).
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/sync/sync_triggers.dart';

void main() {
  late List<bool> calls; // each entry is the `force` flag of one call
  late SyncTriggerScheduler scheduler;

  setUp(() {
    calls = [];
    scheduler = SyncTriggerScheduler(
      runSync: ({bool force = false}) async {
        calls.add(force);
      },
      policy: const SyncTriggerPolicy(localWriteThreshold: 3),
    );
  });

  test('onAppResumed triggers an unforced sync', () {
    scheduler.onAppResumed();
    expect(calls, [false]);
  });

  test('onPullToRefresh always forces, ignoring backoff', () {
    scheduler.onPullToRefresh();
    expect(calls, [true]);
  });

  test('onPeriodicTick triggers an unforced sync', () {
    scheduler.onPeriodicTick();
    expect(calls, [false]);
  });

  test('connectivity: only the none -> connected transition triggers', () {
    scheduler.onConnectivityChanged([ConnectivityResult.none]);
    expect(calls, isEmpty, reason: 'going offline must not trigger a sync');

    scheduler.onConnectivityChanged([ConnectivityResult.wifi]);
    expect(calls, [false], reason: 'regaining connectivity must trigger');

    scheduler.onConnectivityChanged([ConnectivityResult.wifi]);
    expect(
      calls,
      [false],
      reason: 'staying connected must not trigger again',
    );

    scheduler.onConnectivityChanged([ConnectivityResult.none]);
    scheduler.onConnectivityChanged([ConnectivityResult.mobile]);
    expect(
      calls,
      [false, false],
      reason: 'a second none -> connected transition must trigger again',
    );
  });

  test(
      'onLocalWrite triggers only once the threshold is reached, then '
      'resets the counter', () {
    scheduler.onLocalWrite();
    scheduler.onLocalWrite();
    expect(calls, isEmpty);

    scheduler.onLocalWrite(); // 3rd write hits the threshold of 3
    expect(calls, [false]);

    scheduler.onLocalWrite();
    scheduler.onLocalWrite();
    expect(calls, [false], reason: 'counter must have reset after firing');

    scheduler.onLocalWrite();
    expect(calls, [false, false]);
  });
}
