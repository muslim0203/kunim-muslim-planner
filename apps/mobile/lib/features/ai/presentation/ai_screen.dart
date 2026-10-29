import 'package:flutter/material.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../../insights/presentation/insights_view.dart';
import 'ai_analysis_card.dart';

/// The assistant, and the analysis it talks about.
///
/// Two layers, in this order. The card at the top asks the server's analyst
/// what the numbers add up to and what one widget would help; the cards
/// under it are the same picture worked out on the device, which is what the
/// user sees when there is no connection, no key on the server, or no
/// answer. The chat below is still not connected, so it stays visibly
/// inactive rather than pretending.
class AiScreen extends StatelessWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return KunimStatusBarRegion(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(KunimSpacing.lg),
            children: [
              ScreenIntro(
                eyebrow: l10n.aiEyebrow,
                title: l10n.aiGreeting,
                subtitle: l10n.aiSubtitle,
              ),
              const SizedBox(height: KunimSpacing.lg),
              // The assistant first, the device's own analysis under it:
              // the card says the cards below still stand when it cannot
              // answer, so they have to be there to see.
              const AiAnalysisCard(),
              const SizedBox(height: KunimSpacing.xl),
              const InsightsView(),
              const SizedBox(height: KunimSpacing.xl),
              Text(l10n.aiQuickHelp, style: theme.textTheme.titleLarge),
              const SizedBox(height: KunimSpacing.xs),
              Text(
                l10n.aiComingSoonNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: KunimSpacing.md),
              QuickPromptTile(
                title: l10n.aiPriorityPrompt,
                subtitle: l10n.aiPriorityMeta,
                emphasized: true,
              ),
              QuickPromptTile(
                title: l10n.aiHabitPrompt,
                subtitle: l10n.aiHabitMeta,
              ),
              QuickPromptTile(
                title: l10n.aiReflectionPrompt,
                subtitle: l10n.aiReflectionMeta,
              ),
              const SizedBox(height: KunimSpacing.lg),
              TextField(
                enabled: false,
                decoration: InputDecoration(
                  hintText: l10n.aiInputHint,
                  suffixIcon: const Icon(Icons.arrow_upward_rounded),
                ),
              ),
              const SizedBox(height: KunimSpacing.sm),
              Text(
                l10n.aiPrivacy,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
