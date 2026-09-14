/// Device-local prayer reminder settings.
///
/// Stored in the local-only `key_value` table like the other device
/// preferences (`AppSettingsStore`, `PrayerSettingsStore`): reminders are
/// scheduled per device, so these are deliberately NOT routed through
/// `writeWithOutbox`.
library;

import '../../../core/db/app_database.dart';
import '../../prayer/domain/daily_prayer_times.dart';
import '../domain/prayer_reminder_settings.dart';

class PrayerReminderStore {
  PrayerReminderStore(this.db);

  final AppDatabase db;

  static const String enabledKey = 'notify.prayer.enabled';
  static const String prayersKey = 'notify.prayer.prayers';
  static const String leadKey = 'notify.prayer.lead_minutes';

  Future<PrayerReminderSettings> load() async {
    final query = db.select(db.keyValue)
      ..where((row) => row.key.isIn(const [enabledKey, prayersKey, leadKey]));
    final rows = await query.get();
    final byKey = {for (final row in rows) row.key: row.value};
    const defaults = PrayerReminderSettings.defaults;

    final storedPrayers = byKey[prayersKey];
    final lead = int.tryParse(byKey[leadKey] ?? '');
    return PrayerReminderSettings(
      enabled: byKey[enabledKey] == 'true',
      prayers: storedPrayers == null
          ? defaults.prayers
          : {
              for (final kind in PrayerReminderSettings.selectable)
                if (storedPrayers.split(',').contains(kind.name)) kind,
            },
      leadMinutes: PrayerReminderSettings.leadChoices.contains(lead)
          ? lead!
          : defaults.leadMinutes,
    );
  }

  Future<void> save(PrayerReminderSettings settings) {
    return db.transaction(() async {
      await _put(enabledKey, settings.enabled.toString());
      await _put(
        prayersKey,
        [
          for (final PrayerKind kind in PrayerReminderSettings.selectable)
            if (settings.prayers.contains(kind)) kind.name,
        ].join(','),
      );
      await _put(leadKey, settings.leadMinutes.toString());
    });
  }

  Future<void> _put(String key, String value) {
    return db.into(db.keyValue).insertOnConflictUpdate(
          KeyValueCompanion.insert(key: key, value: value),
        );
  }
}
