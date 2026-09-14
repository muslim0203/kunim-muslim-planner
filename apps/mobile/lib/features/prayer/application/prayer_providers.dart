import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../data/prayer_settings_store.dart';
import '../domain/daily_prayer_times.dart';
import '../domain/prayer_settings.dart';

final prayerSettingsStoreProvider = Provider<PrayerSettingsStore>((ref) {
  return PrayerSettingsStore(ref.watch(appDatabaseProvider));
});

class PrayerSettingsController extends AsyncNotifier<PrayerSettings> {
  @override
  Future<PrayerSettings> build() =>
      ref.watch(prayerSettingsStoreProvider).load();

  /// Applies [change] to the current settings, shows the result at once and
  /// saves it.
  Future<void> edit(PrayerSettings Function(PrayerSettings) change) async {
    final current = state.value ?? await future;
    final next = change(current);
    if (next == current) return;
    state = AsyncData(next);
    await ref.read(prayerSettingsStoreProvider).save(next);
  }
}

final prayerSettingsProvider =
    AsyncNotifierProvider<PrayerSettingsController, PrayerSettings>(
  PrayerSettingsController.new,
);

/// The current instant. Overridden in tests to pin "now".
final prayerClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Re-reads the clock once a minute so the next prayer and its countdown
/// move on by themselves.
final prayerMinuteProvider = StreamProvider<DateTime>((ref) async* {
  final clock = ref.watch(prayerClockProvider);
  yield clock();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => clock());
});

/// Today's times for the chosen city, or `null` while no city is chosen.
final todayPrayerProvider = Provider<AsyncValue<PrayerDay?>>((ref) {
  final settings = ref.watch(prayerSettingsProvider);
  final minute = ref.watch(prayerMinuteProvider);
  return settings.whenData((value) {
    final city = value.city;
    if (city == null) return null;
    final instant = minute.value ?? ref.read(prayerClockProvider)();
    return PrayerDay.compute(settings: value, city: city, instant: instant);
  });
});
