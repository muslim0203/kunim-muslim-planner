/// The client-only outbox mechanism: reading/coalescing pending local
/// changes for push, and the local sync cursor/device-id storage the
/// engine needs alongside it (ADR-0002 §2 and §3).
///
/// Rows are written into `sync_outbox` exclusively by
/// `core/db/base_repository.dart#SyncableRepository.writeWithOutbox` — this
/// file only reads, annotates (`attempts`/`last_error`) and removes them.
/// It performs no networking; building/sending the actual HTTP request is
/// `core/sync/sync_engine.dart` (T-204).
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/base_repository.dart';

part 'outbox.g.dart';

/// A single pending local change, decoded from a `sync_outbox` row.
class OutboxEntry {
  const OutboxEntry({
    required this.seq,
    required this.entity,
    required this.rowId,
    required this.op,
    required this.payload,
    required this.attempts,
    this.lastError,
  });

  /// `sync_outbox.seq` — the client-local push order (ADR-0002 §2).
  final int seq;
  final String entity;
  final String rowId;
  final SyncOp op;
  final Map<String, dynamic> payload;
  final int attempts;
  final String? lastError;
}

/// DAO over the `sync_outbox` table (declared in `core/db/app_database.dart`
/// as [SyncOutbox]).
@DriftAccessor(tables: [SyncOutbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  /// All pending outbox rows, oldest first — the delivery order ADR-0002 §2
  /// requires ("push tartibi, klient ichida global").
  Future<List<OutboxEntry>> allPendingOrdered() async {
    final rows = await (select(
      syncOutbox,
    )..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();
    return rows.map(_toEntry).toList(growable: false);
  }

  /// Builds the next push batch.
  ///
  /// Coalesces repeated writes to the same `(entity, rowId)` down to only
  /// the highest-`seq` entry (ADR-0002 §2 "Koalessiya": "bitta `(entity,
  /// row_id)` uchun faqat eng katta `seq` li yozuv yuboriladi" — a later
  /// `delete` simply wins because it IS the highest-seq entry, and a
  /// `delete` is never re-merged with an earlier `upsert`), preserves `seq`
  /// order among the surviving entries, and caps the result at [limit]
  /// distinct rows — the server-provided push limit from `GET
  /// /sync/limits` (ADR-0002 rule 5: local default 200 until that is
  /// wired up by the sync engine).
  ///
  /// Note: this reads the *entire* pending outbox into memory before
  /// coalescing, since the number of distinct rows surviving coalescing
  /// cannot be known from a capped SQL query alone (many stale duplicates
  /// can collapse into one). This is fine for a single-user local outbox;
  /// if that ever becomes a problem, capping the raw SQL scan too (with a
  /// generous multiplier) is the next step.
  Future<List<OutboxEntry>> nextBatch(int limit) async {
    final ordered = await allPendingOrdered();
    final latestBySeq = <String, OutboxEntry>{};
    for (final entry in ordered) {
      // Quarantined entries are NOT candidates. `last_error` is only set by
      // `recordFailure`, which the engine calls for the terminal rejections
      // `schema_invalid` / `payload_too_large` -- ADR-0002 §3 says diagnose
      // those, never resend them. Leaving them in the candidate set let a
      // full batch of unsendable rows block every healthy row queued behind
      // it (head-of-line starvation) while the push loop span for ever.
      //
      // A row edited again AFTER a quarantine gets a fresh entry with a
      // higher seq and no `last_error`, so a corrected row is retried --
      // which is the behaviour we want.
      if (entry.lastError != null) continue;
      // `ordered` is seq-ascending, so the last write here per key is
      // always the highest-seq entry for that (entity, rowId).
      latestBySeq['${entry.entity}|${entry.rowId}'] = entry;
    }
    final coalesced = latestBySeq.values.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    if (coalesced.length <= limit) return coalesced;
    return coalesced.sublist(0, limit);
  }

  /// Removes outbox rows once the server has confirmed them. Per ADR-0002
  /// §3, BOTH `applied` and `conflict` results remove the entry (a
  /// `conflict` is not retried — the client accepts `server_row` and moves
  /// on). Also safe to call with the `seq`s of stale duplicates that
  /// [nextBatch] coalesced away, since a delete of a pending outbox row
  /// simply cleans up state that no longer needs pushing.
  Future<void> acknowledge(Iterable<int> seqs) async {
    if (seqs.isEmpty) return;
    await (delete(syncOutbox)..where((t) => t.seq.isIn(seqs))).go();
  }

  /// Records a failed push attempt: increments `attempts` and stores
  /// `last_error` (surfaced on Settings → Diagnostics per ADR-0002 §2 —
  /// "hech qachon jimgina tashlab yuborilmaydi"). The row is never deleted
  /// here; only [acknowledge] (or an engine-driven `unknown_entity` /
  /// `readonly_entity` / `foreign_user` rejection) removes an outbox entry.
  Future<void> recordFailure(int seq, {required String error}) async {
    await customUpdate(
      'UPDATE sync_outbox SET attempts = attempts + 1, last_error = ? '
      'WHERE seq = ?',
      variables: [Variable<String>(error), Variable<int>(seq)],
      updates: {syncOutbox},
    );
  }

  OutboxEntry _toEntry(SyncOutboxData row) {
    return OutboxEntry(
      seq: row.seq,
      entity: row.entity,
      rowId: row.rowId,
      op: SyncOp.values.byName(row.op),
      payload: jsonDecode(row.payload) as Map<String, dynamic>,
      attempts: row.attempts,
      lastError: row.lastError,
    );
  }
}

/// Local-only sync cursor / device-id storage, built on the existing
/// local-only [KeyValue] table (`core/db/app_database.dart`) — NOT the
/// synced `Preferences` table, since this state is per-installation and
/// must never be pushed to or merged from the server (ADR-0002 §3:
/// `sync_state(user_id, cursor, last_pull_at)` is conceptually server-side
/// bookkeeping mirrored locally, not a syncable entity itself).
class SyncStateStore {
  SyncStateStore(this.db);

  final AppDatabase db;

  static const _cursorKey = 'sync.cursor';
  static const _deviceIdKey = 'sync.device_id';

  /// The last `server_version` this device has fully applied — persisted
  /// as `next_cursor` from `GET /sync/pull`. `0` for a brand-new device,
  /// matching the ADR's "yangi qurilma `cursor = 0` dan boshlaydi".
  Future<int> getCursor() async {
    final raw = await _get(_cursorKey);
    return raw == null ? 0 : int.parse(raw);
  }

  /// Must only be called after a pulled page has been applied inside its
  /// own local transaction (ADR-0002 rule 7: "Klient `next_cursor` ni
  /// faqat sahifa to'liq lokal tranzaksiyada qo'llangandan keyin yozadi").
  Future<void> setCursor(int cursor) => _set(_cursorKey, cursor.toString());

  /// Stable per-install device identifier sent as `device_id` on every push
  /// (ADR-0002 §3). `null` means it has not been generated yet — callers
  /// should generate a UUIDv4 once and persist it via [setDeviceId].
  Future<String?> getDeviceId() => _get(_deviceIdKey);

  Future<void> setDeviceId(String deviceId) => _set(_deviceIdKey, deviceId);

  /// The device id, generated and stored on first use. Login, token
  /// refresh and every push must send the same value: the server ties a
  /// refresh token to the device it was issued to.
  Future<String> getOrCreateDeviceId() async {
    final existing = await getDeviceId();
    if (existing != null) return existing;
    final generated = const Uuid().v4();
    await setDeviceId(generated);
    return generated;
  }

  Future<String?> _get(String key) async {
    final row = await (db.select(
      db.keyValue,
    )..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) async {
    await db.into(db.keyValue).insertOnConflictUpdate(
        KeyValueCompanion.insert(key: key, value: value));
  }
}
