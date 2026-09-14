/// The offline-first sync cycle (ADR-0002 §3): drain the outbox to the
/// server in capped, `seq`-ordered batches, apply the server's per-change
/// answers (`conflict.dart`), then pull server changes back page by page
/// until `has_more` is false, advancing the local cursor only once a page
/// has been fully applied. A single mutex prevents two triggers
/// (`sync_triggers.dart`) from running a cycle concurrently.
///
/// No merge logic lives here either — see the header of `conflict.dart`.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_controller.dart';
import '../db/app_database.dart';
import '../network/error_mapper.dart';
import 'conflict.dart';
import 'outbox.dart';
import 'sync_api.dart';
import 'sync_models.dart';

/// Current state of the sync engine, exposed to the UI via
/// [syncStatusProvider]. A later UI task switches on this exhaustively
/// (it is `sealed`) rather than inspecting engine internals.
sealed class SyncStatus {
  const SyncStatus();
}

/// No cycle has run yet this app session.
final class SyncIdle extends SyncStatus {
  const SyncIdle();
}

/// A cycle is currently in flight.
final class SyncRunning extends SyncStatus {
  const SyncRunning();
}

/// The most recent cycle completed without a transport error. Per-row
/// `rejected` outcomes other than `updated_at_in_future` are still visible
/// via [rejectedTerminally] so a diagnostics screen can surface them
/// without needing its own sync-engine plumbing.
final class SyncSuccess extends SyncStatus {
  const SyncSuccess({
    required this.completedAt,
    required this.rejectedTerminally,
  });

  final DateTime completedAt;
  final int rejectedTerminally;
}

/// A cycle was skipped because another one was already running.
final class SyncSkippedBusy extends SyncStatus {
  const SyncSkippedBusy();
}

/// A cycle was skipped because it is still within the backoff window from
/// a previous transport failure.
final class SyncSkippedBackoff extends SyncStatus {
  const SyncSkippedBackoff(this.retryAt);

  final DateTime retryAt;
}

/// The most recent cycle failed at the transport level. [consecutiveFailures]
/// counts unbroken transport failures across cycles (reset to 0 on any
/// success); once it reaches 10 the task brief's "surface a change after 10
/// failed attempts rather than retrying forever" kicks in via
/// [persistentlyFailing] — the engine keeps retrying on backoff, but the UI
/// should stop treating this as a transient blip.
final class SyncFailed extends SyncStatus {
  const SyncFailed({
    required this.failure,
    required this.consecutiveFailures,
    required this.persistentlyFailing,
    required this.failedAt,
  });

  final ApiFailure failure;
  final int consecutiveFailures;
  final bool persistentlyFailing;
  final DateTime failedAt;
}

const _uuid = Uuid();

/// After how many consecutive transport failures the engine stops treating
/// a failure as "just retry silently" and instead surfaces a persistent
/// state (see [SyncFailed.persistentlyFailing]) — task brief: "surface a
/// change after 10 failed attempts rather than retrying forever".
const _maxConsecutiveFailuresBeforeSurfacing = 10;

/// Exponential backoff schedule matching ADR-0002 §2 (used there for
/// per-row outbox retries; reused here for whole-cycle transport retries):
/// 1s, 2s, 4s, ... capped at 15 minutes.
Duration _backoffDelay(int consecutiveFailures) {
  final capped = consecutiveFailures.clamp(1, 32);
  final seconds = math.min(15 * 60, 1 << (capped - 1));
  return Duration(seconds: seconds);
}

/// Orchestrates one push-then-pull sync cycle. Not itself a Riverpod
/// [Notifier] — [syncEngineProvider] hands out a plain instance, and
/// `sync_triggers.dart`/a UI-facing [SyncStatusController] call [syncOnce]
/// and publish its result.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.api,
    required this.outboxDao,
    required this.stateStore,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final AppDatabase db;
  final SyncApi api;
  final OutboxDao outboxDao;
  final SyncStateStore stateStore;
  final DateTime Function() _now;

  bool _running = false;
  int _consecutiveFailures = 0;
  DateTime? _nextAllowedAttempt;
  SyncLimits? _cachedLimits;

  /// Runs one full cycle: push everything pending, then pull everything
  /// new. Returns without doing network work (a [SyncSkippedBusy] /
  /// [SyncSkippedBackoff]) if a cycle is already running or a previous
  /// transport failure's backoff window hasn't elapsed yet — unless
  /// [force] is set (manual "pull to refresh" / explicit user action).
  Future<SyncStatus> syncOnce({bool force = false}) async {
    if (_running) return const SyncSkippedBusy();

    final now = _now();
    if (!force &&
        _nextAllowedAttempt != null &&
        now.isBefore(_nextAllowedAttempt!)) {
      return SyncSkippedBackoff(_nextAllowedAttempt!);
    }

    _running = true;
    try {
      final limits = await _limits();
      var rejectedTerminally = 0;
      await _pushAll(limits, onOutcome: (o) {
        rejectedTerminally += o.rejectedTerminally;
      });
      await _pullAll(limits);

      _consecutiveFailures = 0;
      _nextAllowedAttempt = null;
      return SyncSuccess(
        completedAt: _now(),
        rejectedTerminally: rejectedTerminally,
      );
    } on SyncApiException catch (e) {
      _consecutiveFailures++;
      _nextAllowedAttempt = _now().add(_backoffDelay(_consecutiveFailures));
      return SyncFailed(
        failure: e.failure,
        consecutiveFailures: _consecutiveFailures,
        persistentlyFailing:
            _consecutiveFailures >= _maxConsecutiveFailuresBeforeSurfacing,
        failedAt: _now(),
      );
    } finally {
      _running = false;
    }
  }

  Future<SyncLimits> _limits() async {
    try {
      final fresh = await api.fetchLimits();
      _cachedLimits = fresh;
      return fresh;
    } on SyncApiException {
      final cached = _cachedLimits;
      if (cached != null) return cached;
      // No cache yet and the server is unreachable: fall back to the
      // ADR's own documented defaults rather than blocking sync entirely.
      // The server remains the primary source (ADR rule 5) whenever it
      // answers.
      return SyncLimits.fallback;
    }
  }

  Future<void> _pushAll(
    SyncLimits limits, {
    required void Function(PushApplyOutcome) onOutcome,
  }) async {
    var iterations = 0;
    while (true) {
      // Read the full pending set *before* coalescing so stale duplicates
      // superseded by this batch's winners can be identified below —
      // `nextBatch` only returns the winners themselves.
      final allPending = await outboxDao.allPendingOrdered();
      if (allPending.isEmpty) return;

      final batch = await outboxDao.nextBatch(limits.maxChangesPerBatch);
      if (batch.isEmpty) return;

      final changes = batch
          .map(
            (entry) => SyncChange(
              clientSeq: entry.seq,
              entity: entry.entity,
              rowId: entry.rowId,
              op: entry.op,
              baseVersion: _baseVersionOf(entry),
              payload: entry.payload,
            ),
          )
          .toList(growable: false);

      final deviceId = await stateStore.getOrCreateDeviceId();
      final response = await api.push(
        SyncPushRequest(
          deviceId: deviceId,
          batchId: _uuid.v4(),
          changes: changes,
        ),
      );

      // ADR-0002 §2 "Koalessiya": once the batch containing the *winning*
      // (highest-seq) entry for a row has been sent successfully, the
      // older superseded duplicates for that same row are dead weight —
      // delete them regardless of what happened to the winner itself,
      // since their content is a strict subset of what was just sent.
      final winnerSeqByKey = {
        for (final entry in batch) '${entry.entity}|${entry.rowId}': entry.seq,
      };
      final staleSeqs = <int>[];
      for (final entry in allPending) {
        final key = '${entry.entity}|${entry.rowId}';
        final winnerSeq = winnerSeqByKey[key];
        if (winnerSeq != null && winnerSeq != entry.seq) {
          staleSeqs.add(entry.seq);
        }
      }
      if (staleSeqs.isNotEmpty) {
        await outboxDao.acknowledge(staleSeqs);
      }

      final outcome = await applyPushResults(
        db: db,
        outboxDao: outboxDao,
        sentBatch: batch,
        results: response.results,
        now: _now,
      );
      onOutcome(outcome);

      // `nextBatch` caps at `limits.maxChangesPerBatch` distinct rows; a
      // short return means the outbox is now fully drained.
      if (batch.length < limits.maxChangesPerBatch) return;

      // Hard bound on iterations, so a cycle can never spin for ever.
      //
      // Terminal rejections drop out of `nextBatch` on their own once
      // `recordFailure` has stamped `last_error` -- that is what stops a full
      // batch of unsendable rows from starving the healthy rows behind it.
      // But a re-stamped `updated_at_in_future` entry is re-queued with a
      // FRESH seq, so on a device whose clock is beyond the server's
      // tolerance that row is rejected, re-stamped and re-sent without end,
      // hammering the server and starving everything else.
      //
      // Stopping early costs at most a deferred attempt: the next trigger
      // (resume, connectivity, timer) starts a new cycle.
      iterations++;
      if (iterations >= _maxPushIterations) {
        _log(
          'push cycle stopped after $iterations iterations with '
          '${batch.length} entries still queued: giving up until the next '
          'trigger (clock skew or a re-queue loop?)',
        );
        return;
      }
    }
  }

  /// Upper bound on `_pushAll` iterations per cycle. Generous enough that a
  /// normal drain (which removes entries every round) never reaches it.
  static const int _maxPushIterations = 50;

  int _baseVersionOf(OutboxEntry entry) {
    final raw =
        entry.payload['server_version'] ?? entry.payload['serverVersion'];
    if (raw is num) return raw.toInt();
    return 0;
  }

  Future<void> _pullAll(SyncLimits limits) async {
    while (true) {
      final cursor = await stateStore.getCursor();
      final response =
          await api.pull(cursor: cursor, limit: limits.maxPullLimit);

      if (response.fullResyncRequired) {
        await _fullResync(limits);
        return;
      }

      // Apply first; only persist the new cursor once the whole page has
      // committed locally (ADR-0002 rule 7) — a crash/throw here must
      // leave the cursor untouched so the same page is re-fetched next
      // time instead of being silently skipped.
      await applyPulledPage(db, response.rows);
      await stateStore.setCursor(response.nextCursor);

      if (!response.hasMore) return;
    }
  }

  /// ADR-0002 §4 mandatory recovery when the cursor fell outside the
  /// server's tombstone-purge window: wipe locally-clean sync rows, reset
  /// the cursor to 0, and pull everything again — while the outbox and any
  /// `dirty = 1` row are left untouched, so an unpushed local edit is never
  /// lost. Partial recovery is explicitly forbidden by the ADR.
  Future<void> _fullResync(SyncLimits limits) async {
    await purgeCleanRows(db);
    await stateStore.setCursor(0);
    await _pullAll(limits);
  }
}

/// Riverpod wiring. `sync_triggers.dart` and any UI code should depend on
/// [syncStatusProvider] (state) and its notifier's [SyncStatusController
/// .runNow] (manual trigger / pull-to-refresh) rather than constructing a
/// [SyncEngine] directly.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncEngine(
    db: db,
    api: ref.watch(syncApiProvider),
    outboxDao: OutboxDao(db),
    stateStore: SyncStateStore(db),
  );
});

/// Publishes the [SyncStatus] of the most recent/current cycle for the UI
/// (e.g. a small "last synced" indicator) and exposes [runNow] as the
/// single manual-trigger entry point (pull-to-refresh, a "sync now"
/// button). `sync_triggers.dart`'s automatic triggers call this same
/// method.
class SyncStatusController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncIdle();

  /// Runs a cycle while an account is signed in; signed out, the app is
  /// local-only and nothing is sent.
  Future<SyncStatus> runNow({bool force = false}) async {
    if (ref.read(authControllerProvider) is! AuthSignedIn) {
      state = const SyncIdle();
      return state;
    }
    state = const SyncRunning();
    SyncStatus result;
    try {
      result = await ref.read(syncEngineProvider).syncOnce(force: force);
    } catch (error) {
      // A failure outside the transport (e.g. applying a page locally) must
      // not leave the status stuck at "running".
      _log('sync cycle failed: ${error.runtimeType}');
      result = SyncFailed(
        failure: UnknownFailure(message: error.runtimeType.toString()),
        consecutiveFailures: 1,
        persistentlyFailing: false,
        failedAt: DateTime.now().toUtc(),
      );
    }
    if (ref.mounted) state = result;
    return result;
  }
}

final syncStatusProvider = NotifierProvider<SyncStatusController, SyncStatus>(
  SyncStatusController.new,
);

void _log(String message) {
  // Entity/rowId/counts only -- never payload contents or tokens.
  developer.log(message, name: 'sync.engine');
}
