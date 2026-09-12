/// When a sync cycle should run. ADR-0002 §2: "app resume, internet
/// qaytdi, foreground'da har 5 daqiqa, N=20 lokal yozuvdan keyin,
/// pull-to-refresh".
///
/// The trigger *policy* ([SyncTriggerScheduler]'s `on...` methods) is kept
/// separate from the real-world *wiring* ([SyncTriggerScheduler.start], a
/// real `Timer`/`Connectivity`/`AppLifecycleListener`) specifically so it
/// is unit-testable without a device, a clock, or a real network — a test
/// can call `onConnectivityChanged(...)`, `onLocalWrite()`, etc. directly
/// against an injected fake `runSync` callback.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_engine.dart';

/// Tunable knobs for [SyncTriggerScheduler], split out so a test can use a
/// short interval/threshold without changing production defaults.
class SyncTriggerPolicy {
  const SyncTriggerPolicy({
    this.periodicInterval = const Duration(minutes: 5),
    this.localWriteThreshold = 20,
  });

  /// ADR-0002 §2: "foreground'da har 5 daqiqa".
  final Duration periodicInterval;

  /// ADR-0002 §2: "N=20 lokal yozuvdan keyin".
  final int localWriteThreshold;
}

/// Decides *when* to call [runSync]; `sync_engine.dart` decides what a
/// cycle actually does. A single instance should be created once per app
/// session (via [syncTriggerSchedulerProvider]) and [start]ed.
class SyncTriggerScheduler {
  SyncTriggerScheduler({
    required this.runSync,
    this.policy = const SyncTriggerPolicy(),
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  /// Runs one sync cycle. Bound to `SyncStatusController.runNow` in
  /// production; a test passes a fake that just records calls.
  final Future<void> Function({bool force}) runSync;
  final SyncTriggerPolicy policy;
  final Connectivity _connectivity;

  int _writesSinceLastSync = 0;
  bool _wasOffline = false;
  Timer? _periodicTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  AppLifecycleListener? _lifecycleListener;

  /// Wires up the real `Timer`/`Connectivity`/app-lifecycle callbacks.
  /// Call once (e.g. from [syncTriggerSchedulerProvider]); call [stop] to
  /// tear down.
  void start() {
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        onAppResumed();
        _resumePeriodicTimer();
      },
      onPause: _pausePeriodicTimer,
      onHide: _pausePeriodicTimer,
      onShow: _resumePeriodicTimer,
    );
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(onConnectivityChanged);
    _resumePeriodicTimer();
  }

  void stop() {
    _pausePeriodicTimer();
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  void _resumePeriodicTimer() {
    _periodicTimer ??= Timer.periodic(
      policy.periodicInterval,
      (_) => onPeriodicTick(),
    );
  }

  void _pausePeriodicTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  // --- Pure trigger policy: exercised directly by tests. ---------------

  /// ADR-0002 §2 "app resume".
  void onAppResumed() => trigger();

  /// ADR-0002 §2 "internet qaytdi" — fires only on the none -> connected
  /// transition, not on every connectivity event.
  void onConnectivityChanged(List<ConnectivityResult> results) {
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (_wasOffline && !offline) trigger();
    _wasOffline = offline;
  }

  /// ADR-0002 §2 "N=20 lokal yozuvdan keyin". A later feature-repository
  /// task calls this after each `writeWithOutbox` completes — the write
  /// count itself cannot be observed from `core/sync` alone, since this
  /// task does not own `core/db`/feature repositories.
  void onLocalWrite() {
    _writesSinceLastSync++;
    if (_writesSinceLastSync >= policy.localWriteThreshold) {
      _writesSinceLastSync = 0;
      trigger();
    }
  }

  /// ADR-0002 §2 "pull-to-refresh" — always forced, ignoring backoff, since
  /// the user explicitly asked for it.
  void onPullToRefresh() => trigger(force: true);

  /// ADR-0002 §2 "foreground'da har 5 daqiqa".
  void onPeriodicTick() => trigger();

  void trigger({bool force = false}) {
    unawaited(runSync(force: force));
  }
}

/// Starts a single [SyncTriggerScheduler] bound to [syncStatusProvider]'s
/// manual-trigger method, and stops it when the provider is disposed.
/// Reading this provider anywhere (e.g. once from the app root widget)
/// is enough to arm every automatic trigger.
final syncTriggerSchedulerProvider = Provider<SyncTriggerScheduler>((ref) {
  final scheduler = SyncTriggerScheduler(
    runSync: ({bool force = false}) {
      return ref.read(syncStatusProvider.notifier).runNow(force: force);
    },
  );
  scheduler.start();
  ref.onDispose(scheduler.stop);
  return scheduler;
});
