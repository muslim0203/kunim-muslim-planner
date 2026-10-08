/// Profile state for the account screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../health/application/health_providers.dart';
import '../../habits/domain/local_day.dart';
import '../data/profile_api.dart';
import '../domain/profile.dart';

/// The signed-in user's profile, fetched from the server.
final profileProvider = FutureProvider<Profile>(
  (ref) => ref.watch(profileApiProvider).fetch(),
);

/// The most recently logged weight, in kilograms, or null if never logged.
///
/// Read from `health_logs` rather than the profile: weight is a dated
/// measurement, and the chart is built from the same rows, so the number on
/// the profile and the last point on the chart can never disagree.
final latestWeightProvider = Provider<AsyncValue<double?>>((ref) {
  final logs = ref.watch(recentHealthLogsProvider);
  return logs.whenData((entries) {
    for (final entry in entries.reversed) {
      final weight = entry.weightKg;
      if (weight != null) return weight;
    }
    return null;
  });
});

/// Saves a new weight as today's health log, the same row the health screen
/// and the chart write to.
final weightWriterProvider = Provider<Future<void> Function(double)>((ref) {
  return (double kilograms) async {
    await ref
        .read(healthLogRepositoryProvider)
        .saveForDay(LocalDay.now(), weightKg: kilograms);
  };
});
