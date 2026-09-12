import 'package:flutter/material.dart';

/// Material 3 color schemes generated from a single seed color, per
/// `docs/plan.md` section 2 ("Material 3 `ColorScheme.fromSeed`").
///
/// The seed is the prayer module green, since prayer is the app's central
/// pillar; module screens layer their own accent color (see `tokens.dart`)
/// on top of this base scheme.
const Color _seedColor = Color(0xFF2E7D32);

final ColorScheme kunimLightColorScheme = ColorScheme.fromSeed(
  seedColor: _seedColor,
  brightness: Brightness.light,
);

final ColorScheme kunimDarkColorScheme = ColorScheme.fromSeed(
  seedColor: _seedColor,
  brightness: Brightness.dark,
);
