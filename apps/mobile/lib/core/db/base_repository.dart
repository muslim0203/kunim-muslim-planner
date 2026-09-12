/// The single sanctioned write path for syncable rows.
///
/// ADR-0002 ("Amalga oshirish uchun majburiy qoidalar" §1) / `CLAUDE.md`
/// rule 2: **a local row write and its `sync_outbox` entry must always
/// happen in one Drift transaction.** A repository must never write a row
/// without also writing its outbox entry — this file is the only place
/// that invariant is implemented.
library;

import 'dart:convert';

import 'app_database.dart';

/// The two outbox operations defined by ADR-0002 §2. The wire value sent to
/// the server is always `op.name` ('upsert' or 'delete') — the enum member
/// names are chosen to match the ADR's JSON literals exactly, so neither
/// this file nor `core/sync/sync_models.dart` needs a separate string
/// mapping.
enum SyncOp { upsert, delete }

/// Base class for feature repositories that write rows to syncable tables
/// (`tasks`, `habits`, `goals`, ... — see `docs/plan.md` §3).
///
/// Subclasses must route every insert/update/soft-delete of a syncable
/// table through [writeWithOutbox] and expose only intention-revealing
/// methods to callers (e.g. `addTask`, `completeTask`), never raw
/// `into(table)`/`update(table)` access. See the class-level doc on
/// [writeWithOutbox] for what this does and does not protect against.
abstract class SyncableRepository {
  SyncableRepository(this.db);

  final AppDatabase db;

  /// Writes a row and its `sync_outbox` entry atomically.
  ///
  /// [write] performs the actual table insert/update/soft-delete and must
  /// not commit anything on its own (it runs inside the same transaction
  /// as the outbox insert). [payload] is the row's full state as it will
  /// be sent to the server — it must NOT contain `dirty` (client-only per
  /// ADR-0002 §1); use [syncPayload] to strip it from a row's JSON before
  /// calling this. If either the row write or the outbox insert throws,
  /// the whole transaction rolls back and NEITHER is persisted — that is
  /// the entire point of this method.
  ///
  /// Structural safeguards against bypass:
  /// - Both writes always happen inside `db.transaction`, so a failure at
  ///   either step rolls back both (proven against a real, in-memory
  ///   database by `test/sync/outbox_invariant_test.dart`, including the
  ///   failure path — not just the happy path).
  /// - [payload] is checked at runtime (not just `assert`, so this also
  ///   holds in release builds) to reject an accidental `dirty` key.
  ///
  /// What this does NOT protect against (see the task report for the
  /// follow-up recommendation): Drift generates a public `into(db.tasks)`/
  /// `update(db.tasks)` API directly on [AppDatabase], and Dart has no
  /// "visible to this library only" access modifier that could hide it
  /// from a feature file that imports `app_database.dart`. A developer can
  /// still write `db.into(db.tasks).insert(...)` directly, skipping the
  /// outbox entirely. Closing that gap needs either a custom_lint rule
  /// (banning `db.into`/`db.update`/`db.delete` calls outside
  /// `core/db/base_repository.dart` and code generated from it) or
  /// wrapping every table in a private accessor class that is the only
  /// thing exported from `core/db` — neither exists yet.
  Future<T> writeWithOutbox<T>({
    required String entity,
    required String rowId,
    required SyncOp op,
    required Map<String, dynamic> payload,
    required Future<T> Function() write,
  }) {
    if (payload.containsKey('dirty')) {
      throw ArgumentError.value(
        payload,
        'payload',
        'dirty is client-only per ADR-0002 §1 and must never be sent to '
            'the server — strip it with syncPayload() before calling '
            'writeWithOutbox().',
      );
    }
    return db.transaction(() async {
      final result = await write();
      await db.into(db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              entity: entity,
              rowId: rowId,
              op: op.name,
              payload: jsonEncode(payload),
            ),
          );
      return result;
    });
  }

  /// Escape hatch reserved for the sync engine (`core/sync/sync_engine.dart`,
  /// T-204) when it applies server-confirmed state: pulled rows and
  /// `conflict` responses' `server_row`. Those writes must NOT create a new
  /// outbox entry — re-queuing data the server just sent would push it
  /// straight back and loop forever. This is a plain transactional write
  /// with no outbox side effect.
  ///
  /// Feature repositories must NEVER call this for a user-initiated change:
  /// doing so silently drops the write from sync, which is exactly the bug
  /// class [writeWithOutbox] exists to prevent. If a future developer wires
  /// this up from a feature's `data/` layer instead of `core/sync`, that is
  /// a bypass of the outbox invariant that no test in this task can catch
  /// (it requires knowing the *caller's intent*, not just observing the
  /// database) — code review must catch it.
  Future<T> writeFromServer<T>(Future<T> Function() write) {
    return db.transaction(write);
  }
}

/// Strips the client-only `dirty` column from a row's JSON representation
/// before it is used as an outbox payload. ADR-0002 §1: `dirty` "hech qachon
/// serverga yuborilmaydi" (never sent to the server; the server schema does
/// not even have the column).
Map<String, dynamic> syncPayload(Map<String, dynamic> rowJson) {
  final copy = Map<String, dynamic>.from(rowJson)..remove('dirty');
  return copy;
}
