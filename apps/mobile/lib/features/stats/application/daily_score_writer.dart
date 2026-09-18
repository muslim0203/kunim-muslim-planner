/// Keeps today's `daily_scores` row in step with the score this device
/// computed, so the leaderboard has something to add up.
///
/// The row is a report of local work: the rules live in
/// `domain/daily_score.dart` and nothing reads the stored points back to
/// display them. `DailyScoreRepository.saveForDay` skips a write when the
/// stored row already says the same, so a rebuild that changes nothing never
/// queues an outbox entry.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_triggers.dart';
import '../data/daily_score_repository.dart';
import '../domain/daily_score.dart';
import 'activity_providers.dart';
import 'weekly_stats_provider.dart';

final dailyScoreRepositoryProvider = Provider<DailyScoreRepository>((ref) {
  return DailyScoreRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

/// Watched once from the app root; writing is a side effect of the score
/// changing, so it lives in a listener rather than in a provider's build.
class DailyScoreWriter extends Notifier<void> {
  @override
  void build() {
    ref.listen<ScoreBoard>(
      scoreBoardProvider,
      (_, board) => unawaited(_write(board)),
      fireImmediately: true,
    );
  }

  Future<void> _write(ScoreBoard board) async {
    if (board.days.isEmpty) return;
    final today = board.days.last;
    try {
      await ref.read(dailyScoreRepositoryProvider).saveForDay(
            ref.read(statsTodayProvider),
            points: today.points,
            done: today.done,
            planned: today.planned,
          );
    } catch (error) {
      // A score that fails to save is not worth interrupting the app for;
      // the next change writes it again.
      debugPrint("Today's score not saved: ${error.runtimeType}");
    }
  }
}

final dailyScoreWriterProvider = NotifierProvider<DailyScoreWriter, void>(
  DailyScoreWriter.new,
);
