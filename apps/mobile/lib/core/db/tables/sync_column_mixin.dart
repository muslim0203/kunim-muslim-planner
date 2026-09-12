import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

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
  TextColumn get id => text().clientDefault(() => _uuid.v4())();

  TextColumn get userId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  IntColumn get serverVersion => integer().withDefault(const Constant(0))();

  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
}
