import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'color_schemes.dart';
import 'tokens.dart';

/// Current [ThemeMode] selection. Defaults to following the system setting;
/// Phase 1 wires this to `preferences` (synced) instead of a bare provider.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Material 3 theming for KUNIM, light and dark variants.
abstract final class KunimTheme {
  static ThemeData light = _build(kunimLightColorScheme);
  static ThemeData dark = _build(kunimDarkColorScheme);

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: KunimRadii.mediumRadius,
        ),
        margin: const EdgeInsets.all(KunimSpacing.sm),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(kMinTouchTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: KunimRadii.mediumRadius,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(kMinTouchTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: KunimRadii.mediumRadius,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(kMinTouchTarget),
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
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: KunimRadii.mediumRadius,
        ),
      ),
    );
  }
}
