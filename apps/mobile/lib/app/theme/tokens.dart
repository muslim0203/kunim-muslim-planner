/// Design tokens for KUNIM (Phase 0).
///
/// Source of truth: `docs/plan.md` section 2 ("Dizayn tizimi") — minimalist,
/// card-based UI, each module has its own accent color, radius 16-20.
library;

import 'package:flutter/material.dart';

/// Per-module accent colors. Each feature module keeps a stable identity
/// color across light/dark themes (used for icons, progress rings, chips —
/// never as the only signal, per accessibility rule in the plan).
abstract final class KunimModuleColors {
  /// Prayer / namoz.
  static const Color prayer = Color(0xFF2E7D32); // green
  /// Quran.
  static const Color quran = Color(0xFF1565C0); // blue
  /// Mood / ruhiy holat.
  static const Color mood = Color(0xFF6A1B9A); // purple
  /// Family / oila.
  static const Color family = Color(0xFFC62828); // red
  /// Health / sog'liq.
  static const Color health = Color(0xFF00796B); // teal
  /// Work / ish.
  static const Color work = Color(0xFFF9A825); // yellow
  /// Sleep / uyqu.
  static const Color sleep = Color(0xFF283593); // indigo
}

/// Corner radii used across cards, sheets and buttons.
abstract final class KunimRadii {
  static const double small = 12;
  static const double medium = 16;
  static const double large = 20;

  static const BorderRadius mediumRadius =
      BorderRadius.all(Radius.circular(medium));
  static const BorderRadius largeRadius =
      BorderRadius.all(Radius.circular(large));
}

/// Spacing scale (logical pixels), used instead of ad-hoc padding values.
abstract final class KunimSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Minimum touch target size required by the accessibility rule in the plan
/// (>= 48dp for every interactive control).
const double kMinTouchTarget = 48;
