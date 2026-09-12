import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Shared sync-tracking columns every syncable table must have, per
/// `CLAUDE.md` ("Sync jadvallarida majburiy: id UUID, user_id, created_at,
/// updated_at (UTC), deleted_at, server_version BIGINT") and
/// `docs/plan.md` section 3 (offline-first sync).
///
/// Usage: `class MyTable extends Table with SyncColumns { ... }`. The
/// mixin only declares columns — the owning table still declares its own
/// `primaryKey` (usually `{id}`) and any feature-specific columns.
///
/// Column semantics:
/// - [id]: client-generated UUID v4, primary key, stable across sync.
/// - [userId]: owner of the row; nullable in Phase 0 (no auth yet).
/// - [createdAt] / [updatedAt]: UTC timestamps, set/touched locally.
/// - [deletedAt]: soft-delete marker (tombstone), null while alive.
/// - [serverVersion]: last version number acknowledged by the server;
///   0 until the row has synced at least once.
/// - [dirty]: true while this row has local changes not yet pushed to the
///   server (the outbox is the actual delivery queue; this flag is a quick
///   local marker used by repositories/UI, e.g. a "syncing" indicator).
mixin SyncColumns on Table {
  // NOTE: `drift_dev` re-emits this closure's source text verbatim into
  // `app_database.g.dart` (a `part of app_database.dart`), so it can ONLY
  // reference symbols that `app_database.dart` itself imports — NOT
  // anything private to this file. `const Uuid()` from `package:uuid`
  // (imported directly by `app_database.dart`) works; a private top-level
  // helper here does not (it fails at compile time with "getter '_x' isn't
  // defined", since the generated code lives in a different library).
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  TextColumn get userId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  IntColumn get serverVersion => integer().withDefault(const Constant(0))();

  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
}
