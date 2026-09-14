/// "Ruhiy holat": one mood check-in per day (a 1-5 score, feelings and a
/// note), with earlier days below. No advice or diagnosis is ever shown.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/db/app_database.dart';
import '../../../shared/widgets/daily_log_screen.dart';
import '../../habits/domain/local_day.dart';
import '../application/mood_providers.dart';
import '../data/mood_log_repository.dart';
import '../domain/mood_options.dart';

class MoodScreen extends ConsumerWidget {
  const MoodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return DailyLogScreen<MoodLog>(
      title: l10n.moduleMood,
      intro: l10n.moodIntro,
      today: ref.watch(todayMoodLogProvider),
      recent: ref.watch(recentMoodLogsProvider),
      dateOf: (entry) => entry.date,
      summaryOf: (context, entry) => _MoodSummary(entry: entry),
      onEdit: (entry) => showDailyLogEditor(
        context,
        MoodEditor(
          day: entry == null
              ? LocalDay.now()
              : LocalDay.fromUtcMidnight(entry.date),
          entry: entry,
        ),
      ),
    );
  }
}

abstract final class MoodLabels {
  static IconData icon(int score) {
    return switch (score) {
      1 => Icons.sentiment_very_dissatisfied_rounded,
      2 => Icons.sentiment_dissatisfied_rounded,
      3 => Icons.sentiment_neutral_rounded,
      4 => Icons.sentiment_satisfied_rounded,
      _ => Icons.sentiment_very_satisfied_rounded,
    };
  }

  static String score(AppLocalizations l10n, int score) {
    return switch (score) {
      1 => l10n.moodScore1,
      2 => l10n.moodScore2,
      3 => l10n.moodScore3,
      4 => l10n.moodScore4,
      _ => l10n.moodScore5,
    };
  }

  /// Unknown codes (from a newer app version) show as the code itself.
  static String tag(AppLocalizations l10n, String code) {
    return switch (code) {
      'calm' => l10n.moodTagCalm,
      'happy' => l10n.moodTagHappy,
      'grateful' => l10n.moodTagGrateful,
      'energetic' => l10n.moodTagEnergetic,
      'focused' => l10n.moodTagFocused,
      'tired' => l10n.moodTagTired,
      'anxious' => l10n.moodTagAnxious,
      'sad' => l10n.moodTagSad,
      'irritated' => l10n.moodTagIrritated,
      'stressed' => l10n.moodTagStressed,
      _ => code,
    };
  }
}

class _MoodSummary extends StatelessWidget {
  const _MoodSummary({required this.entry});

  final MoodLog entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tags = MoodLogRepository.tagsOf(entry)
        .map((code) => MoodLabels.tag(l10n, code));
    return Row(
      children: [
        Icon(MoodLabels.icon(entry.score), color: KunimModuleColors.mood),
        const SizedBox(width: KunimSpacing.sm),
        Expanded(
          child: Text(
            [MoodLabels.score(l10n, entry.score), ...tags].join(', '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class MoodEditor extends ConsumerStatefulWidget {
  const MoodEditor({super.key, required this.day, this.entry});

  final LocalDay day;
  final MoodLog? entry;

  @override
  ConsumerState<MoodEditor> createState() => _MoodEditorState();
}

class _MoodEditorState extends ConsumerState<MoodEditor> {
  int? _score;
  late final Set<String> _tags;
  late final TextEditingController _note;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _score = entry?.score;
    _tags =
        entry == null ? <String>{} : MoodLogRepository.tagsOf(entry).toSet();
    _note = TextEditingController(text: entry?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DailyLogEditorFrame(
      title: dailyLogDayTitle(context, widget.day.toUtcMidnight()),
      error: _error,
      onSave: _score == null ? null : _save,
      onDelete: widget.entry == null ? null : _delete,
      children: [
        DailyLogSection(
          title: l10n.moodQuestion,
          child: Wrap(
            spacing: KunimSpacing.sm,
            runSpacing: KunimSpacing.sm,
            children: [
              for (var score = MoodOptions.minScore;
                  score <= MoodOptions.maxScore;
                  score++)
                ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(MoodLabels.icon(score)),
                  label: Text(MoodLabels.score(l10n, score)),
                  selected: _score == score,
                  onSelected: (_) => setState(() => _score = score),
                ),
            ],
          ),
        ),
        DailyLogSection(
          title: l10n.moodFeelings,
          child: Wrap(
            spacing: KunimSpacing.sm,
            runSpacing: KunimSpacing.sm,
            children: [
              for (final code in {...MoodOptions.tags, ..._tags})
                FilterChip(
                  label: Text(MoodLabels.tag(l10n, code)),
                  selected: _tags.contains(code),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _tags.add(code);
                    } else {
                      _tags.remove(code);
                    }
                  }),
                ),
            ],
          ),
        ),
        DailyLogNoteField(controller: _note),
      ],
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(moodLogRepositoryProvider).saveForDay(
            widget.day,
            score: _score!,
            tags: _tags,
            note: _note.text,
          );
      navigator.pop();
    } on ArgumentError {
      if (mounted) setState(() => _error = l10n.logSaveFailed);
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    if (!await confirmDailyLogDelete(context)) return;
    await ref.read(moodLogRepositoryProvider).deleteForDay(widget.day);
    navigator.pop();
  }
}
