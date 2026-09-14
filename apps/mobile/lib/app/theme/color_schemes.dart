import 'package:flutter/material.dart';

/// Material 3 color schemes generated from a single seed color, per
/// `docs/plan.md` section 2 ("Material 3 `ColorScheme.fromSeed`").
///
/// The seed is the prayer module green, since prayer is the app's central
/// pillar; module screens layer their own accent color (see `tokens.dart`)
/// on top of this base scheme.
const Color _seedColor = Color(0xFF0E6B5E);

final ColorScheme kunimLightColorScheme = ColorScheme.fromSeed(
  seedColor: _seedColor,
  brightness: Brightness.light,
).copyWith(
  primary: const Color(0xFF0E6B5E),
  onPrimary: Colors.white,
  primaryContainer: const Color(0xFFDDF3EC),
  onPrimaryContainer: const Color(0xFF0B3D35),
  secondary: const Color(0xFFC6922B),
  secondaryContainer: const Color(0xFFF8EFD4),
  surface: const Color(0xFFFFFCF5),
  surfaceContainerHigh: Colors.white,
  outlineVariant: const Color(0xFFEEE4D2),
);

final ColorScheme kunimDarkColorScheme = ColorScheme.fromSeed(
  seedColor: _seedColor,
  brightness: Brightness.dark,
).copyWith(
  primary: const Color(0xFF63D0B7),
  onPrimary: const Color(0xFF073B33),
  primaryContainer: const Color(0xFF103F3A),
  onPrimaryContainer: const Color(0xFFDDF3EC),
  secondary: const Color(0xFFE8C979),
  secondaryContainer: const Color(0xFF3A321D),
  surface: const Color(0xFF071A24),
  surfaceContainerHigh: const Color(0xFF102C37),
  outlineVariant: const Color(0xFF38545E),
);
