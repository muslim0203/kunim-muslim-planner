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
  static const Color prayer = Color(0xFF0E6B5E);

  /// Quran.
  static const Color quran = Color(0xFF3E4D8F);

  /// Mood / ruhiy holat.
  static const Color mood = Color(0xFF7952B3);

  /// Family / oila.
  static const Color family = Color(0xFFA5423C);

  /// Health / sog'liq.
  static const Color health = Color(0xFF26718C);

  /// Work / ish.
  static const Color work = Color(0xFFC6922B);

  /// Sleep / uyqu.
  static const Color sleep = Color(0xFF4856A6);
}

/// KUNIM brand palette, kept in step with the Figma library.
abstract final class KunimColors {
  static const Color midnight = Color(0xFF0B1F2A);
  static const Color ink = Color(0xFF102C37);
  static const Color inkMuted = Color(0xFF38545E);
  static const Color jade = Color(0xFF0E6B5E);
  static const Color jadeBright = Color(0xFF15947F);
  static const Color jadeSoft = Color(0xFFDDF3EC);
  static const Color gold = Color(0xFFC6922B);
  static const Color goldSoft = Color(0xFFF8EFD4);
  static const Color ivory = Color(0xFFFFFCF5);
  static const Color sand = Color(0xFFEEE4D2);
}

/// Corner radii used across cards, sheets and buttons.
abstract final class KunimRadii {
  static const double small = 12;
  static const double medium = 16;
  static const double large = 20;
  static const double extraLarge = 28;

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
