import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n/gen/app_localizations.dart';
import '../../app/theme/tokens.dart';

/// Status bar icon style that stays legible over content of
/// [backgroundBrightness]: dark icons on light screens, light icons on dark
/// screens and photos.
SystemUiOverlayStyle kunimOverlayStyleFor(Brightness backgroundBrightness) {
  final base = backgroundBrightness == Brightness.dark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark;
  return base.copyWith(statusBarColor: Colors.transparent);
}

/// Wraps a screen without an [AppBar] so the status bar icons match the
/// screen background instead of inheriting whatever the previous screen set.
class KunimStatusBarRegion extends StatelessWidget {
  const KunimStatusBarRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kunimOverlayStyleFor(Theme.of(context).brightness),
      child: child,
    );
  }
}

class ScreenIntro extends StatelessWidget {
  const ScreenIntro({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.secondary,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: KunimSpacing.xs),
        Text(title, style: theme.textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: KunimSpacing.xs),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Outlined surface card. With a null [onTap] it is not interactive at all
/// (no ripple, not announced as a button).
class HeritageCard extends StatelessWidget {
  const HeritageCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KunimSpacing.lg),
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KunimRadii.large),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Small pill telling the user a section exists but is not built yet. Used
/// instead of a chevron so an unfinished feature never looks tappable.
class ComingSoonBadge extends StatelessWidget {
  const ComingSoonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KunimSpacing.sm,
        vertical: KunimSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        AppLocalizations.of(context).comingSoon,
        maxLines: 1,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A labelled value with a progress bar. Not wrapped in [Expanded]: the
/// caller decides how it is laid out.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.progress,
    this.caption,
  });

  final String label;
  final String value;
  final Color color;

  /// `null` hides the bar (no meaningful ratio, e.g. no data yet).
  final double? progress;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(KunimSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: theme.brightness == Brightness.dark ? .2 : .12,
        ),
        borderRadius: BorderRadius.circular(KunimRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: KunimSpacing.sm),
          Text(value, style: theme.textTheme.titleLarge),
          if (caption != null) ...[
            const SizedBox(height: KunimSpacing.xs),
            Text(caption!, style: theme.textTheme.bodySmall),
          ],
          if (progress != null) ...[
            const SizedBox(height: KunimSpacing.md),
            LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(99),
              backgroundColor: theme.colorScheme.surface.withValues(alpha: .7),
              color: color,
            ),
          ],
        ],
      ),
    );
  }
}

/// A suggested prompt. With a null [onTap] it renders as inactive: muted
/// text and no chevron, so it never promises an action that does nothing.
class QuickPromptTile extends StatelessWidget {
  const QuickPromptTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.emphasized = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final titleColor = enabled ? scheme.onSurface : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
      child: HeritageCard(
        color: emphasized ? scheme.primaryContainer : null,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: KunimSpacing.xs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (enabled)
              Icon(Icons.chevron_right_rounded, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class HeritageArcPainter extends CustomPainter {
  const HeritageArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x88E8C979), Color(0x00C6922B)],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .82, size.height * .2),
          radius: size.width * .45,
        ),
      );
    canvas.drawCircle(
      Offset(size.width * .82, size.height * .2),
      size.width * .45,
      glow,
    );

    final line = Paint()
      ..color = KunimColors.gold.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(size.width * .83, size.height * .54),
        64 + i * 34,
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A bottom sheet listing [options] with a check next to [selected]. Returns
/// the picked value, or `null` if the sheet was dismissed.
Future<T?> showKunimChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required T? selected,
  required List<(T, String)> options,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // Above the shell's bottom navigation bar, which would otherwise cover
    // the last options of a long list.
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: KunimSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: KunimSpacing.lg),
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: KunimSpacing.sm),
              for (final (value, label) in options)
                ListTile(
                  title: Text(label),
                  selected: value == selected,
                  trailing: value == selected
                      ? Icon(
                          Icons.check_rounded,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(value),
                ),
            ],
          ),
        ),
      );
    },
  );
}
