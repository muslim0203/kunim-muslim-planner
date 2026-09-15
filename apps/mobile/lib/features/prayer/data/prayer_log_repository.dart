/// Data access for `PrayerLogs`: at most one live mark per prayer per local
/// day.
///
/// ADR-0002 rule 10: natural key `(user_id, ref_id, date)`, `ref_id` being the
/// prayer key. The server merges `status` as an ordered enum, max-wins, so an
/// update can never lower a mark. Lowering one is therefore written as a
/// tombstone of the old row plus a fresh row: the server's natural-key lookup
/// ignores tombstones, so the fresh row is applied as it is. Every read
/// filters `deletedAt.isNull()`.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/base_repository.dart';
import '../../../core/db/local_write_hook.dart';
import '../../../core/sync/conflict.dart' show toRfc3339Millis, toWireDate;
import '../../habits/domain/local_day.dart';
import '../domain/prayer_log_status.dart';

class PrayerLogRepository extends SyncableRepository with LocalWriteHook {
  PrayerLogRepository(
    super.db, {
    required this.onLocalWrite,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  @override
  final void Function() onLocalWrite;
  final DateTime Function() _now;

  static const String entityName = 'prayer_logs';

  /// The live marks of [day], keyed by prayer key. A status code this build
  /// does not know is left out.
  Stream<Map<String, PrayerLogStatus>> watchDay(LocalDay day) {
    final query = db.select(db.prayerLogs)
      ..where(
        (l) => l.date.equals(day.toUtcMidnight()) & l.deletedAt.isNull(),
      );
    return query.watch().map(
          (rows) => {
            for (final row in rows)
              if (PrayerLogStatus.fromCode(row.status) case final status?)
                row.refId: status,
          },
        );
  }

  /// Live marks from [since] on, oldest day first.
  Stream<List<PrayerLog>> watchSince(LocalDay since) {
    final query = db.select(db.prayerLogs)
      ..where(
        (l) =>
            l.deletedAt.isNull() &
            l.date.isBiggerOrEqualValue(since.toUtcMidnight()),
      )
      ..orderBy([(l) => OrderingTerm.asc(l.date)]);
    return query.watch();
  }

  /// Marks [prayerKey] on [day] as [status], replacing an earlier mark.
  Future<PrayerLog> mark(
    LocalDay day,
    String prayerKey,
    PrayerLogStatus status, {
    String? userId,
  }) async {
    if (!prayerLogKeys.contains(prayerKey)) {
      throw ArgumentError.value(prayerKey, 'prayerKey');
    }
    final now = _now().toUtc();
    final existing = await _live(day, prayerKey).getSingleOrNull();

    if (existing != null) {
      final current = PrayerLogStatus.fromCode(existing.status);
      if (current == status) return existing;
      if (current != null && status.index > current.index) {
        final patch = PrayerLogsCompanion(
          status: Value(status.code),
          updatedAt: Value(now),
          dirty: const Value(true),
        );
        final merged = existing.copyWithCompanion(patch);
        await writeAndNotify<void>(
          entity: entityName,
          rowId: existing.id,
          op: SyncOp.upsert,
          payload: _payloadOf(merged),
          write: () => (db.update(db.prayerLogs)
                ..where((l) => l.id.equals(existing.id)))
              .write(patch),
        );
        return merged;
      }
      // Lower (or unknown) mark: see the library comment.
      await _tombstone(existing, now);
    }

    final row = PrayerLog(
      id: const Uuid().v4(),
      userId: userId,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      serverVersion: 0,
      dirty: true,
      refId: prayerKey,
      date: day.toUtcMidnight(),
      status: status.code,
      note: null,
    );
    await writeAndNotify<void>(
      entity: entityName,
      rowId: row.id,
      op: SyncOp.upsert,
      payload: _payloadOf(row),
      write: () => db.into(db.prayerLogs).insert(row.toCompanion(false)),
    );
    return row;
  }

  /// Takes back [prayerKey]'s mark on [day], if any.
  Future<void> clear(LocalDay day, String prayerKey) async {
    final existing = await _live(day, prayerKey).getSingleOrNull();
    if (existing == null) return;
    await _tombstone(existing, _now().toUtc());
  }

  Future<void> _tombstone(PrayerLog existing, DateTime now) {
    final patch = PrayerLogsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      dirty: const Value(true),
    );
    return writeAndNotify<void>(
      entity: entityName,
      rowId: existing.id,
      op: SyncOp.delete,
      payload: _payloadOf(existing.copyWithCompanion(patch)),
      write: () => (db.update(db.prayerLogs)
            ..where((l) => l.id.equals(existing.id)))
          .write(patch),
    );
  }

  SimpleSelectStatement<$PrayerLogsTable, PrayerLog> _live(
    LocalDay day,
    String prayerKey,
  ) {
    return db.select(db.prayerLogs)
      ..where(
        (l) =>
            l.date.equals(day.toUtcMidnight()) &
            l.refId.equals(prayerKey) &
            l.deletedAt.isNull(),
      )
      ..limit(1);
  }

  /// Snake_case wire row (ADR-0002 §3); `date` is a DATE.
  Map<String, dynamic> _payloadOf(PrayerLog row) => {
        'id': row.id,
        'user_id': row.userId,
        'ref_id': row.refId,
        'date': toWireDate(row.date),
        'status': row.status,
        'note': row.note,
        'created_at': toRfc3339Millis(row.createdAt),
        'updated_at': toRfc3339Millis(row.updatedAt),
        'deleted_at':
            row.deletedAt == null ? null : toRfc3339Millis(row.deletedAt!),
        'server_version': row.serverVersion,
      };
}
