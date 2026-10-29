/// The assistant's card: ask, read, and take what is useful.
///
/// It sits above the offline analysis, never instead of it. Whatever happens
/// here — no connection, no key on the server, a refused answer — the cards
/// below still tell the user which areas are holding and which are
/// slipping, because those are computed on the device. So every failure in
/// this card is one calm line, not an empty screen.
///
/// A proposed widget is created only when the user taps add, and then by the
/// ordinary local write path. Nothing on this card writes anything by
/// itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../../habits/presentation/habit_kind_labels.dart';
import '../../insights/application/insight_providers.dart';
import '../../onboarding/presentation/onboarding_labels.dart';
import '../application/ai_analysis_controller.dart';
import '../data/ai_api.dart';
import '../domain/ai_analysis.dart';
import '../domain/analysis_facts.dart';

class AiAnalysisCard extends ConsumerWidget {
  const AiAnalysisCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(aiAnalysisControllerProvider);

    return Container(
      constraints: const BoxConstraints(minHeight: 168),
      // Clip so the decorative arcs stay inside the rounded card.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KunimRadii.extraLarge),
        gradient: const LinearGradient(
          colors: [KunimColors.jade, KunimColors.ink],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: HeritageArcPainter()),
          ),
          Padding(
            padding: const EdgeInsets.all(KunimSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: KunimColors.goldSoft,
                      size: 32,
                    ),
                    const Spacer(),
                    if (state.isLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KunimColors.goldSoft,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: KunimSpacing.lg),
                if (state.isLoading)
                  ..._loading(l10n, theme)
                else if (state.error != null)
                  ..._failed(context, ref, l10n, theme, state.error!)
                else if (state.hasAnalysis)
                  ..._answer(context, ref, l10n, theme, state)
                else
                  ..._idle(context, ref, l10n, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Before anything has been asked for. The hint says what the analysis is
  /// made of, because an assistant that will not say where its numbers come
  /// from should not be trusted with a day.
  List<Widget> _idle(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return [
      Text(
        l10n.aiTodayQuestion,
        style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
      ),
      const SizedBox(height: KunimSpacing.sm),
      Text(
        l10n.aiAnalyseHint(insightWindowDays),
        style: const TextStyle(color: KunimColors.jadeSoft),
      ),
      const SizedBox(height: KunimSpacing.lg),
      _AskButton(
        label: l10n.aiAnalyseAction,
        onPressed: () => _ask(context, ref),
      ),
    ];
  }

  List<Widget> _loading(AppLocalizations l10n, ThemeData theme) {
    return [
      Text(
        l10n.aiAnalysing,
        style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
      ),
      const SizedBox(height: KunimSpacing.sm),
      Text(
        l10n.aiAnalyseWait,
        style: const TextStyle(color: KunimColors.jadeSoft),
      ),
    ];
  }

  /// One line and one button. Which of the four server failures it was is
  /// the server's business; what the user needs to know is that the analysis
  /// below still stands.
  List<Widget> _failed(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
    AiErrorKind kind,
  ) {
    final message = switch (kind) {
      AiErrorKind.network => l10n.aiErrorNetwork,
      AiErrorKind.unauthorized => l10n.authErrorSessionExpired,
      AiErrorKind.unavailable => l10n.aiErrorUnavailable,
      AiErrorKind.quotaExceeded => l10n.aiErrorQuota,
      AiErrorKind.notEnoughData => l10n.aiErrorNotEnoughData,
    };

    return [
      Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
      ),
      // Nothing to retry when the device simply has not recorded enough, or
      // when the session is gone: both need something else from the user
      // first.
      if (kind != AiErrorKind.notEnoughData &&
          kind != AiErrorKind.unauthorized) ...[
        const SizedBox(height: KunimSpacing.lg),
        _AskButton(
          label: l10n.aiErrorRetry,
          onPressed: () => _ask(context, ref),
        ),
      ],
    ];
  }

  List<Widget> _answer(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
    AiAnalysisState data,
  ) {
    final analysis = data.proposal!.analysis;

    return [
      if (analysis.summary.isNotEmpty)
        Text(
          analysis.summary,
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
        ),
      for (final note in analysis.areas) ...[
        const SizedBox(height: KunimSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              focusAreaIcon(note.area),
              size: 18,
              color: KunimColors.goldSoft,
            ),
            const SizedBox(width: KunimSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    focusAreaLabel(l10n, note.area),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: KunimColors.goldSoft,
                    ),
                  ),
                  Text(
                    note.note,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      if (analysis.widgets.isNotEmpty && !data.allDecided) ...[
        const SizedBox(height: KunimSpacing.lg),
        Text(
          l10n.aiProposalsTitle,
          style: theme.textTheme.labelMedium?.copyWith(
            color: KunimColors.goldSoft,
          ),
        ),
        for (var index = 0; index < analysis.widgets.length; index++)
          if (!data.accepted.contains(index) && !data.rejected.contains(index))
            _ProposalRow(
              proposal: analysis.widgets[index],
              onAccept: () => ref
                  .read(aiAnalysisControllerProvider.notifier)
                  .acceptWidget(index),
              onReject: () => ref
                  .read(aiAnalysisControllerProvider.notifier)
                  .rejectWidget(index),
            ),
      ],
      if (data.accepted.isNotEmpty) ...[
        const SizedBox(height: KunimSpacing.md),
        Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 18,
              color: KunimColors.goldSoft,
            ),
            const SizedBox(width: KunimSpacing.sm),
            Expanded(
              child: Text(
                l10n.aiProposalAdded(data.accepted.length),
                style: const TextStyle(color: KunimColors.jadeSoft),
              ),
            ),
          ],
        ),
      ],
      // The summary quotes the counts it was measured from. Once a widget
      // is ticked those counts move, and the cards under this one recompute
      // while the paid summary cannot — so say which moment it describes
      // rather than letting the two disagree in silence.
      if (_isStale(ref, data)) ...[
        const SizedBox(height: KunimSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.history_rounded,
                size: 18, color: KunimColors.goldSoft),
            const SizedBox(width: KunimSpacing.sm),
            Expanded(
              child: Text(
                l10n.aiAnalysisOutdated,
                style: const TextStyle(color: KunimColors.goldSoft),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: KunimSpacing.lg),
      // Says what the answer is and is not. The server enforces the second
      // half of this sentence (`app/ai/safety/religious_guard.py`); saying it
      // here is how the user knows to expect it.
      Text(
        l10n.aiAnalysisFootnote,
        style: theme.textTheme.bodySmall?.copyWith(color: KunimColors.jadeSoft),
      ),
      const SizedBox(height: KunimSpacing.sm),
      _AskButton(
        label: l10n.aiAnalyseAgain,
        onPressed: () => _ask(context, ref),
      ),
    ];
  }

  /// Whether the counts behind the shown summary have moved since it came
  /// back. Rebuilt from the same providers the facts were assembled from,
  /// so no extra bookkeeping has to be kept in step.
  bool _isStale(WidgetRef ref, AiAnalysisState data) {
    final facts = AnalysisFacts.from(
      insights: ref.watch(areaInsightsProvider),
      observations: ref.watch(areaObservationsProvider),
      windowDays: insightWindowDays,
      // Only `countsDigest` is read from this, and the locale plays no part
      // in it.
      locale: '',
      answers: ref.watch(insightAnswersProvider),
    );
    return data.isStaleAgainst(facts.countsDigest);
  }

  void _ask(BuildContext context, WidgetRef ref) {
    ref.read(aiAnalysisControllerProvider.notifier).analyse(
          // The language on screen right now, not the account's: the user
          // reads the answer here.
          locale: AppLocalizations.of(context).localeName,
        );
  }
}

class _AskButton extends StatelessWidget {
  const _AskButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// One proposed widget: what it is, why, and the two taps it allows.
class _ProposalRow extends StatelessWidget {
  const _ProposalRow({
    required this.proposal,
    required this.onAccept,
    required this.onReject,
  });

  final AiWidgetProposal proposal;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: KunimSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                habitKindIcon(proposal.kind),
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: KunimSpacing.sm),
              Expanded(
                child: Text(
                  proposal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                ),
              ),
              Text(
                habitAmount(l10n, proposal.kind, proposal.dailyTarget),
                style: const TextStyle(color: KunimColors.jadeSoft),
              ),
            ],
          ),
          if (proposal.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                proposal.reason,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: KunimColors.jadeSoft,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: KunimSpacing.xs),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.aiProposalAccept),
                ),
                const SizedBox(width: KunimSpacing.sm),
                TextButton(
                  onPressed: onReject,
                  child: Text(
                    l10n.aiProposalReject,
                    style: const TextStyle(color: KunimColors.jadeSoft),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
