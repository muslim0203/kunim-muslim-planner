import 'package:adhan_dart/adhan_dart.dart' show Madhab;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/prayer/application/prayer_providers.dart';
import 'package:kunim/features/prayer/data/prayer_settings_store.dart';
import 'package:kunim/features/prayer/domain/prayer_city.dart';
import 'package:kunim/features/prayer/domain/prayer_settings.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('nothing stored: no city, Hanafi, the default method', () async {
    final settings = await PrayerSettingsStore(db).load();

    expect(settings, PrayerSettings.defaults);
    expect(settings.city, isNull);
    expect(settings.madhab, Madhab.hanafi);
  });

  test('round-trips every field', () async {
    const saved = PrayerSettings(
      city: PrayerCity.samarkand,
      method: PrayerMethod.karachi,
      madhab: Madhab.shafi,
    );
    await PrayerSettingsStore(db).save(saved);

    expect(await PrayerSettingsStore(db).load(), saved);
  });

  test('saving without a city removes the stored one', () async {
    final store = PrayerSettingsStore(db);
    await store.save(
      PrayerSettings.defaults.copyWith(city: PrayerCity.bukhara),
    );
    await store.save(PrayerSettings.defaults);

    expect((await store.load()).city, isNull);
  });

  test('unknown stored codes fall back to the defaults', () async {
    for (final key in const [
      PrayerSettingsStore.cityKey,
      PrayerSettingsStore.methodKey,
      PrayerSettingsStore.madhabKey,
    ]) {
      await db
          .into(db.keyValue)
          .insert(KeyValueCompanion.insert(key: key, value: 'unknown'));
    }

    expect(await PrayerSettingsStore(db).load(), PrayerSettings.defaults);
  });

  test('the controller shows and saves an edit', () async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await container.read(prayerSettingsProvider.future);
    await container
        .read(prayerSettingsProvider.notifier)
        .edit((settings) => settings.copyWith(city: PrayerCity.nukus));

    expect(
        container.read(prayerSettingsProvider).value?.city, PrayerCity.nukus);
    expect((await PrayerSettingsStore(db).load()).city, PrayerCity.nukus);
  });
}
