/// Riverpod wiring for the calendar feature — the only place under
/// `features/calendar/` that touches `flutter_riverpod` or
/// `core/sync/sync_triggers.dart`. See `data/calendar_event_repository.dart`
/// for the actual reads/writes and `domain/recurrence.dart` for the RRULE
/// expansion applied here.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_triggers.dart';
import '../data/calendar_event_repository.dart';
import '../domain/recurrence.dart';

final calendarEventRepositoryProvider =
    Provider<CalendarEventRepository>((ref) {
  return CalendarEventRepository(
    ref.watch(appDatabaseProvider),
    onLocalWrite: () => ref.read(syncTriggerSchedulerProvider).onLocalWrite(),
  );
});

/// Expanded occurrences (recurrence included) of every non-deleted event
/// touching `[range.start, range.end]` (both inclusive), sorted by start
/// time. Recomputed whenever the underlying `calendar_events` rows change
/// — see `CalendarEventRepository.watchEventsOverlapping`.
///
/// The family key is a record (`({DateTime start, DateTime end})`) rather
/// than a bespoke class: Dart records already have value-based
/// `==`/`hashCode`, which is exactly what Riverpod's `.family` needs to
/// cache/re-key providers correctly.
final eventsInRangeProvider = StreamProvider.family<List<CalendarOccurrence>,
    ({DateTime start, DateTime end})>((
  ref,
  range,
) {
  final repo = ref.watch(calendarEventRepositoryProvider);
  return repo
      .watchEventsOverlapping(rangeStart: range.start, rangeEnd: range.end)
      .map((events) {
    final occurrences = <CalendarOccurrence>[
      for (final event in events)
        ...expandEventOccurrences(event,
            rangeStart: range.start, rangeEnd: range.end),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return occurrences;
  });
});

/// Mutation entry point for calendar screens — same idle/loading/error
/// pattern as `features/goals/application/goals_providers.dart`'s
/// `GoalsController`.
class CalendarEventsController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  CalendarEventRepository get _events =>
      ref.read(calendarEventRepositoryProvider);

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(action);
  }

  Future<void> createEvent({
    required String title,
    String? description,
    required DateTime startAt,
    DateTime? endAt,
    bool allDay = false,
    String? rrule,
    String? location,
  }) {
    return _run(
      () => _events.createEvent(
        title: title,
        description: description,
        startAt: startAt,
        endAt: endAt,
        allDay: allDay,
        rrule: rrule,
        location: location,
      ),
    );
  }

  Future<void> updateEvent({
    required String id,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? startAt,
    Value<DateTime?> endAt = const Value.absent(),
    bool? allDay,
    Value<String?> rrule = const Value.absent(),
    Value<String?> location = const Value.absent(),
  }) {
    return _run(
      () => _events.updateEvent(
        id: id,
        title: title,
        description: description,
        startAt: startAt,
        endAt: endAt,
        allDay: allDay,
        rrule: rrule,
        location: location,
      ),
    );
  }

  Future<void> deleteEvent(String id) {
    return _run(() => _events.deleteEvent(id));
  }
}

final calendarEventsControllerProvider =
    NotifierProvider<CalendarEventsController, AsyncValue<void>>(
        CalendarEventsController.new);
