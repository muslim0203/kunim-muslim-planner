/// The sign-up answers, kept on the device.
///
/// The account holds a copy so a second phone starts from the same picture,
/// but this one is the copy the app reads: the analysis must work with no
/// connection, and asking the server for the user's own answers would make a
/// local screen wait on a network call it does not need.
///
/// Stored in the local-only `key_value` table, like the other per-device
/// settings — never routed through the outbox.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../domain/onboarding_answers.dart';

class OnboardingAnswersStore {
  OnboardingAnswersStore(this.db);

  final AppDatabase db;

  static const String occupationKey = 'onboarding.occupation';
  static const String interestsKey = 'onboarding.interests';
  static const String focusAreasKey = 'onboarding.focus_areas';
  static const String minutesKey = 'onboarding.daily_minutes';

  Future<OnboardingAnswers> load() async {
    final query = db.select(db.keyValue)
      ..where(
        (row) => row.key.isIn(const [
          occupationKey,
          interestsKey,
          focusAreasKey,
          minutesKey,
        ]),
      );
    final rows = await query.get();
    final byKey = {for (final row in rows) row.key: row.value};

    return OnboardingAnswers.fromSlugs(
      occupation: byKey[occupationKey],
      interests: _slugs(byKey[interestsKey]),
      focusAreas: _slugs(byKey[focusAreasKey]),
      dailyMinutes: int.tryParse(byKey[minutesKey] ?? ''),
    );
  }

  Future<void> save(OnboardingAnswers answers) async {
    await _put(occupationKey, answers.occupation?.slug ?? '');
    await _put(
      interestsKey,
      [for (final interest in answers.interests) interest.slug].join(','),
    );
    await _put(
      focusAreasKey,
      [for (final area in answers.focusAreas) area.slug].join(','),
    );
    await _put(minutesKey, answers.budget.toString());
  }

  Future<void> _put(String key, String value) {
    return db
        .into(db.keyValue)
        .insertOnConflictUpdate(
          KeyValueCompanion.insert(key: key, value: value),
        );
  }

  static List<String> _slugs(String? stored) {
    if (stored == null || stored.isEmpty) return const [];
    return [
      for (final slug in stored.split(','))
        if (slug.isNotEmpty) slug,
    ];
  }
}

final onboardingAnswersStoreProvider = Provider<OnboardingAnswersStore>((ref) {
  return OnboardingAnswersStore(ref.watch(appDatabaseProvider));
});

/// What this device remembers being answered. Empty on a device where the
/// questions were skipped — which simply means the analysis reports only
/// what it can measure.
final savedOnboardingAnswersProvider = FutureProvider<OnboardingAnswers>((ref) {
  return ref.watch(onboardingAnswersStoreProvider).load();
});
