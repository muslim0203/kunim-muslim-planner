/// Device-local prayer settings: city, calculation method and Asr madhab.
///
/// Stored in the local-only `key_value` table for the same reason as
/// `AppSettingsStore`: they are per-device preferences, not synced user
/// content, so they are deliberately NOT routed through `writeWithOutbox`.
/// When `preferences.prayer_settings` starts syncing (`docs/plan.md`
/// section 6), this store becomes the offline cache in front of it.
library;

import 'package:adhan_dart/adhan_dart.dart' show Madhab;

import '../../../core/db/app_database.dart';
import '../domain/prayer_city.dart';
import '../domain/prayer_settings.dart';

class PrayerSettingsStore {
  PrayerSettingsStore(this.db);

  final AppDatabase db;

  static const String cityKey = 'prayer.city';
  static const String methodKey = 'prayer.method';
  static const String madhabKey = 'prayer.madhab';

  Future<PrayerSettings> load() async {
    final query = db.select(db.keyValue)
      ..where((row) => row.key.isIn(const [cityKey, methodKey, madhabKey]));
    final rows = await query.get();
    final byKey = {for (final row in rows) row.key: row.value};
    return PrayerSettings(
      city: PrayerCity.fromCode(byKey[cityKey]),
      method: PrayerMethod.fromCode(byKey[methodKey]),
      madhab: _madhabFrom(byKey[madhabKey]),
    );
  }

  Future<void> save(PrayerSettings settings) {
    return db.transaction(() async {
      final city = settings.city;
      if (city == null) {
        await (db.delete(db.keyValue)..where((row) => row.key.equals(cityKey)))
            .go();
      } else {
        await _put(cityKey, city.code);
      }
      await _put(methodKey, settings.method.code);
      await _put(madhabKey, settings.madhab.name);
    });
  }

  Future<void> _put(String key, String value) {
    return db.into(db.keyValue).insertOnConflictUpdate(
          KeyValueCompanion.insert(key: key, value: value),
        );
  }

  static Madhab _madhabFrom(String? name) => Madhab.values.firstWhere(
        (madhab) => madhab.name == name,
        orElse: () => PrayerSettings.defaults.madhab,
      );
}
