import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// A rounded, padded surface used across module screens (Home, Day, etc.).
///
/// Wraps [child] in a `Card`-like container using the shared [KunimRadii]
/// and [KunimSpacing] tokens instead of ad-hoc values, so every module
/// looks consistent regardless of its accent color.
class KunimCard extends StatelessWidget {
  const KunimCard({
    super.key,
    required this.child,
    this.accentColor,
    this.padding = const EdgeInsets.all(KunimSpacing.lg),
    this.onTap,
  });

  final Widget child;

  /// Optional module accent color (see [KunimModuleColors]), rendered as a
  /// thin left border so color is never the only signal (accessibility).
  final Color? accentColor;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = accentColor == null
        ? null
        : Border(left: BorderSide(color: accentColor!, width: 4));

    final content = Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: KunimRadii.mediumRadius,
        border: border,
      ),
      padding: padding,
      child: child,
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      borderRadius: KunimRadii.mediumRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: KunimRadii.mediumRadius,
        child: content,
      ),
    );
  }
}
