import 'package:flutter/material.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/kunim_widgets.dart';

/// Preview of the AI assistant. The assistant is not connected yet, so every
/// control here is visibly inactive and labelled as coming soon.
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
              const SizedBox(height: KunimSpacing.xl),
              Container(
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
                          const Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: KunimColors.goldSoft,
                                size: 32,
                              ),
                              Spacer(),
                              ComingSoonBadge(),
                            ],
                          ),
                          const SizedBox(height: KunimSpacing.xl),
                          Text(
                            l10n.aiTodayQuestion,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: KunimSpacing.sm),
                          Text(
                            l10n.aiTodayCopy,
                            style: const TextStyle(color: KunimColors.jadeSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
