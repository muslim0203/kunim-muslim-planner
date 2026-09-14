/// Device-local app settings: interface language and theme mode.
///
/// Both live in the local-only `key_value` table (see `AppDatabase`), for the
/// same reason `TaskTopThreeStore` does: they are per-device UI preferences,
/// not synced user content, so they are deliberately NOT routed through
/// `writeWithOutbox`. When `preferences.ui` starts syncing in a later phase,
/// this store becomes the offline cache in front of it.
///
/// Uzbek (Latin script) is the product's primary language, so it is the
/// default regardless of the device locale; the user can switch in Settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';

/// Interface languages shipped at launch (`docs/plan.md` section 2).
enum AppLanguage {
  uz('uz'),
  uzCyrl('uz_Cyrl'),
  ru('ru'),
  en('en');

  const AppLanguage(this.code);

  /// Stable storage code. Never rename an existing value.
  final String code;

  Locale get locale => switch (this) {
        AppLanguage.uz => const Locale('uz'),
        AppLanguage.uzCyrl =>
          const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'),
        AppLanguage.ru => const Locale('ru'),
        AppLanguage.en => const Locale('en'),
      };

  /// Unknown or missing codes fall back to the primary language.
  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
        (language) => language.code == code,
        orElse: () => AppLanguage.uz,
      );
}

@immutable
class AppSettings {
  const AppSettings({required this.language, required this.themeMode});

  static const AppSettings defaults = AppSettings(
    language: AppLanguage.uz,
    themeMode: ThemeMode.system,
  );

  final AppLanguage language;
  final ThemeMode themeMode;

  AppSettings copyWith({AppLanguage? language, ThemeMode? themeMode}) {
    return AppSettings(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(language, themeMode);
}

class AppSettingsStore {
  AppSettingsStore(this.db);

  final AppDatabase db;

  static const String languageKey = 'settings.language';
  static const String themeModeKey = 'settings.theme_mode';

  Future<AppSettings> load() async {
    final query = db.select(db.keyValue)
      ..where((row) => row.key.isIn(const [languageKey, themeModeKey]));
    final rows = await query.get();
    final byKey = {for (final row in rows) row.key: row.value};
    return AppSettings(
      language: AppLanguage.fromCode(byKey[languageKey]),
      themeMode: _themeModeFrom(byKey[themeModeKey]),
    );
  }

  Future<void> saveLanguage(AppLanguage language) =>
      _put(languageKey, language.code);

  Future<void> saveThemeMode(ThemeMode mode) => _put(themeModeKey, mode.name);

  Future<void> _put(String key, String value) {
    return db.into(db.keyValue).insertOnConflictUpdate(
          KeyValueCompanion.insert(key: key, value: value),
        );
  }

  static ThemeMode _themeModeFrom(String? name) => ThemeMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => ThemeMode.system,
      );
}

final appSettingsStoreProvider = Provider<AppSettingsStore>((ref) {
  return AppSettingsStore(ref.watch(appDatabaseProvider));
});

/// Settings loaded before the first frame. `main.dart` overrides this with
/// the stored values so the app never flashes the wrong language; tests and
/// any other entry point get [AppSettings.defaults].
final initialAppSettingsProvider = Provider<AppSettings>(
  (ref) => AppSettings.defaults,
);

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialAppSettingsProvider);

  Future<void> setLanguage(AppLanguage language) async {
    if (state.language == language) return;
    state = state.copyWith(language: language);
    await ref.read(appSettingsStoreProvider).saveLanguage(language);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state.themeMode == mode) return;
    state = state.copyWith(themeMode: mode);
    await ref.read(appSettingsStoreProvider).saveThemeMode(mode);
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);
