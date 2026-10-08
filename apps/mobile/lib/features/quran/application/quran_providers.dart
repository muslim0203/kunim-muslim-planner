/// What the Qur'an screens read: the index, one page at a time, and where the
/// reader left off.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../data/quran_position_store.dart';
import '../data/quran_repository.dart';
import '../domain/quran_models.dart';

final quranPositionStoreProvider = Provider<QuranPositionStore>((ref) {
  return QuranPositionStore(ref.watch(appDatabaseProvider));
});

/// The 114 surahs, read once and kept for the session.
final quranSurahsProvider = FutureProvider<List<Surah>>((ref) {
  ref.keepAlive();
  return ref.watch(quranRepositoryProvider).surahs();
});

final quranJuzsProvider = FutureProvider<List<Juz>>((ref) {
  ref.keepAlive();
  return ref.watch(quranRepositoryProvider).juzs();
});

/// One mushaf page. Pages are cached so flipping back is instant, but only a
/// few live at a time — the reader watches the page it shows and its
/// neighbours, and the rest are dropped.
final quranPageProvider = FutureProvider.family<QuranPage, int>((ref, page) {
  return ref.watch(quranRepositoryProvider).page(page);
});

/// Where the text came from, for the reader's source line.
final quranEditionProvider = FutureProvider<QuranEdition>((ref) {
  ref.keepAlive();
  return ref.watch(quranRepositoryProvider).edition();
});

/// The last page read on this device, or null when it has never been opened.
class QuranPositionController extends AsyncNotifier<QuranPosition?> {
  @override
  Future<QuranPosition?> build() =>
      ref.watch(quranPositionStoreProvider).load();

  /// Remembers [page]. Called as the reader flips, so it shows the new page
  /// at once and writes behind it.
  Future<void> remember(int page, {int? ayahId}) async {
    final position =
        QuranPosition(page: Mushaf.clampPage(page), ayahId: ayahId);
    state = AsyncData(position);
    await ref.read(quranPositionStoreProvider).save(position);
  }
}

final quranPositionProvider =
    AsyncNotifierProvider<QuranPositionController, QuranPosition?>(
  QuranPositionController.new,
);
