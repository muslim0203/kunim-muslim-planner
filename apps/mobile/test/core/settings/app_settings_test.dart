import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/settings/app_settings.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('AppSettingsStore', () {
    test('an empty database yields Uzbek Latin and the system theme', () async {
      final settings = await AppSettingsStore(db).load();
      expect(settings.language, AppLanguage.uz);
      expect(settings.themeMode, ThemeMode.system);
    });

    test('saved language and theme survive a reload', () async {
      final store = AppSettingsStore(db);
      await store.saveLanguage(AppLanguage.uzCyrl);
      await store.saveThemeMode(ThemeMode.dark);

      final reloaded = await AppSettingsStore(db).load();
      expect(reloaded.language, AppLanguage.uzCyrl);
      expect(reloaded.themeMode, ThemeMode.dark);
    });

    test('unknown stored values fall back to the defaults', () async {
      await db.into(db.keyValue).insertOnConflictUpdate(
            KeyValueCompanion.insert(
              key: AppSettingsStore.languageKey,
              value: 'klingon',
            ),
          );
      await db.into(db.keyValue).insertOnConflictUpdate(
            KeyValueCompanion.insert(
              key: AppSettingsStore.themeModeKey,
              value: 'sepia',
            ),
          );

      final settings = await AppSettingsStore(db).load();
      expect(settings, AppSettings.defaults);
    });
  });

  group('AppLanguage', () {
    test('Uzbek Cyrillic maps to the uz-Cyrl script locale', () {
      expect(
        AppLanguage.uzCyrl.locale,
        const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'),
      );
      expect(AppLanguage.uz.locale, const Locale('uz'));
    });
  });

  group('AppSettingsController', () {
    test('changes state immediately and persists it', () async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      expect(container.read(appSettingsProvider), AppSettings.defaults);

      await container
          .read(appSettingsProvider.notifier)
          .setLanguage(AppLanguage.ru);
      await container
          .read(appSettingsProvider.notifier)
          .setThemeMode(ThemeMode.light);

      expect(container.read(appSettingsProvider).language, AppLanguage.ru);
      expect(container.read(appSettingsProvider).themeMode, ThemeMode.light);

      final stored = await AppSettingsStore(db).load();
      expect(stored.language, AppLanguage.ru);
      expect(stored.themeMode, ThemeMode.light);
    });

    test('starts from the settings loaded before the first frame', () {
      const loaded = AppSettings(
        language: AppLanguage.en,
        themeMode: ThemeMode.dark,
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          initialAppSettingsProvider.overrideWithValue(loaded),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(appSettingsProvider), loaded);
    });
  });
}
