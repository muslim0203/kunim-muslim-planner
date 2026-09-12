import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'color_schemes.dart';
import 'tokens.dart';

/// Current [ThemeMode] selection. Defaults to following the system setting.
///
/// Riverpod 3 removed `StateProvider`, so this is a plain [Notifier]. Phase 1
/// replaces the in-memory default with the synced `preferences.ui.theme` value.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

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
