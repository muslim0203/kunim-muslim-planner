/// Where the reader left off, kept on this device.
///
/// Stored in the local-only `key_value` table like the other per-device
/// preferences: a reading position belongs to the device you read on, and
/// syncing it would make two phones fight over a page number. (The plan's
/// `quran_progress` sync table is about a khatm plan and pages read per day,
/// which is a different thing and lands with that feature.)
library;

import '../../../core/db/app_database.dart';
import '../domain/quran_models.dart';

class QuranPositionStore {
  QuranPositionStore(this.db);

  final AppDatabase db;

  static const String pageKey = 'quran.last_page';
  static const String ayahKey = 'quran.last_ayah';

  Future<QuranPosition?> load() async {
    final query = db.select(db.keyValue)
      ..where((row) => row.key.isIn(const [pageKey, ayahKey]));
    final rows = await query.get();
    final byKey = {for (final row in rows) row.key: row.value};
    final page = int.tryParse(byKey[pageKey] ?? '');
    if (page == null) return null;
    return QuranPosition(
      page: Mushaf.clampPage(page),
      ayahId: int.tryParse(byKey[ayahKey] ?? ''),
    );
  }

  Future<void> save(QuranPosition position) async {
    await _put(pageKey, position.page.toString());
    final ayah = position.ayahId;
    if (ayah != null) await _put(ayahKey, ayah.toString());
  }

  Future<void> _put(String key, String value) {
    return db.into(db.keyValue).insertOnConflictUpdate(
          KeyValueCompanion.insert(key: key, value: value),
        );
  }
}
