/// Data-layer access to the `calendar_events` table (ADR-0002 §1 /
/// `docs/sync-conflict-matrix.md` rule 20: plain LWW + soft delete — no
/// natural-key/additive-field merge like `habit_logs` etc.). See
/// `features/goals/data/goal_repository.dart`'s class doc for the shared
/// `writeWithOutbox` + `onLocalWrite` pattern.
///
/// Recurrence ([CalendarEvents.rrule]) is stored and synced as a single
/// opaque string on the one event row — see `domain/recurrence.dart` for
/// how it is expanded into concrete occurrences. This repository only
/// ever reads/writes that one row; it never materializes occurrences as
/// rows of their own.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';

const _uuid = Uuid();

class CalendarEventRepository extends SyncableRepository {
  CalendarEventRepository(
    super.db, {
    this.onLocalWrite,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final void Function()? onLocalWrite;
  final DateTime Function() _now;

  /// Non-deleted events whose own span could contribute at least one
  /// occurrence to `[rangeStart, rangeEnd]` — a coarse, reactive
  /// pre-filter; `domain/recurrence.dart` does the actual per-occurrence
  /// expansion (recurrence included) over the rows this returns.
  ///
  /// A recurring event ([CalendarEvents.rrule] non-null) can never
  /// produce an occurrence before its own [CalendarEvents.startAt], but
  /// CAN produce one arbitrarily far after it — so `startAt <= rangeEnd`
  /// is the only safe (non-lossy) filter for it, regardless of how far in
  /// the future [rangeEnd] is. A one-off event additionally needs its own
  /// span (`[startAt, endAt ?? startAt]`) to overlap the range.
  Stream<List<CalendarEvent>> watchEventsOverlapping({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final query = db.select(db.calendarEvents)
      ..where(
        (e) =>
            e.deletedAt.isNull() &
            e.startAt.isSmallerOrEqualValue(rangeEnd) &
            (e.rrule.isNotNull() |
                (e.endAt.isNull() &
                    e.startAt.isBiggerOrEqualValue(rangeStart)) |
                (e.endAt.isNotNull() &
                    e.endAt.isBiggerOrEqualValue(rangeStart))),
      )
      ..orderBy([(e) => OrderingTerm(expression: e.startAt)]);
    return query.watch();
  }

  /// A single event by id, or `null` if it does not exist locally.
  Stream<CalendarEvent?> watchById(String id) {
    final query = db.select(db.calendarEvents)..where((e) => e.id.equals(id));
    return query.watchSingleOrNull();
  }

  Future<CalendarEvent> createEvent({
    required String title,
    String? description,
    required DateTime startAt,
    DateTime? endAt,
    bool allDay = false,
    String? rrule,
    String? location,
    String? userId,
  }) {
    final now = _now();
    final row = CalendarEvent(
      id: _uuid.v4(),
      userId: userId,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      serverVersion: 0,
      dirty: true,
      title: title,
      description: description,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      rrule: rrule,
      location: location,
    );
    return _persist(row);
  }

  /// Updates fields of an existing event. The nullable columns
  /// ([description], [endAt], [rrule], [location]) use Drift's `Value`
  /// wrapper so a caller can distinguish "leave unchanged"
  /// ([Value.absent]) from "explicitly clear" (`Value(null)`) — e.g.
  /// `rrule: const Value(null)` turns a recurring event back into a
  /// one-off. [title]/[startAt]/[allDay] are plain nullable params where
  /// `null` means "leave unchanged". Throws [StateError] if [id] does not
  /// exist locally.
  Future<CalendarEvent> updateEvent({
    required String id,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? startAt,
    Value<DateTime?> endAt = const Value.absent(),
    bool? allDay,
    Value<String?> rrule = const Value.absent(),
    Value<String?> location = const Value.absent(),
  }) async {
    final existing = await _require(id);
    final updated = existing.copyWith(
      title: title,
      description: description,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      rrule: rrule,
      location: location,
      updatedAt: _now(),
    );
    return _persist(updated);
  }

  /// Soft-deletes an event. A no-op if it is already deleted or does not
  /// exist locally.
  Future<void> deleteEvent(String id) async {
    final existing = await (db.select(db.calendarEvents)
          ..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (existing == null || existing.deletedAt != null) return;

    final now = _now();
    final updated = existing.copyWith(deletedAt: Value(now), updatedAt: now);
    await writeWithOutbox<void>(
      entity: 'calendar_events',
      rowId: id,
      op: SyncOp.delete,
      payload: syncPayload(updated.toJson()),
      write: () => db.update(db.calendarEvents).replace(updated),
    );
    onLocalWrite?.call();
  }

  Future<CalendarEvent> _require(String id) async {
    final existing = await (db.select(db.calendarEvents)
          ..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      throw StateError('Calendar event not found: $id');
    }
    return existing;
  }

  Future<CalendarEvent> _persist(CalendarEvent row) async {
    final result = await writeWithOutbox<CalendarEvent>(
      entity: 'calendar_events',
      rowId: row.id,
      op: SyncOp.upsert,
      payload: syncPayload(row.toJson()),
      write: () async {
        await db.into(db.calendarEvents).insertOnConflictUpdate(row);
        return row;
      },
    );
    onLocalWrite?.call();
    return result;
  }
}
