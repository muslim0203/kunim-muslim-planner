import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'color_schemes.dart';
import 'tokens.dart';

/// Material 3 theming for KUNIM, light and dark variants.
///
/// Theme mode and language live in `core/settings/app_settings.dart`.
abstract final class KunimTheme {
  static ThemeData light =
      _build(kunimLightColorScheme, fontFamily: _brandFont);
  static ThemeData dark = _build(kunimDarkColorScheme, fontFamily: _brandFont);

  /// Variants on the platform font for Uzbek Cyrillic. Manrope has no glyphs
  /// for Ҳ ҳ, Қ қ and Ғ ғ, so those letters would otherwise be drawn in a
  /// fallback font in the middle of Manrope words.
  static ThemeData lightSystemFont = _build(kunimLightColorScheme);
  static ThemeData darkSystemFont = _build(kunimDarkColorScheme);

  static const String _brandFont = 'Manrope';

  static ThemeData _build(ColorScheme scheme, {String? fontFamily}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: fontFamily,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: KunimRadii.largeRadius,
        ),
        margin: const EdgeInsets.all(KunimSpacing.sm),
      ),
      // NOTE: the minimum here constrains *height* only. `Size.fromHeight`
      // must not be used: it expands to `Size(double.infinity, h)`, which
      // gives every button an infinite minimum width. Inside a `Row` that
      // overflows the row, collapses any `Spacer` and pushes later children
      // off-screen (it hid the task editor's Save button entirely).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, kMinTouchTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: KunimRadii.mediumRadius,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, kMinTouchTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: KunimRadii.mediumRadius,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, kMinTouchTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: KunimRadii.mediumRadius,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(kMinTouchTarget),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: KunimRadii.mediumRadius,
        ),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // The bar is transparent, so AppBar cannot infer icon contrast from
        // its own colour; state it from the page background instead.
        systemOverlayStyle: (scheme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent),
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerHigh,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            // Explicit size: text geometry is only merged into `textTheme`
            // entries, so a style taken from it and used elsewhere has no
            // fontSize and silently renders at 14sp. At 11sp with no extra
            // tracking every label fits one line on a 390dp phone in all four
            // languages (see test/app/layout_matrix_test.dart).
            fontSize: 11,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
