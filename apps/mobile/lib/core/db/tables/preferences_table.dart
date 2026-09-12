import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// Simple user-preference key/value rows (e.g. selected locale, theme mode,
/// notification toggles) that must survive re-installs via the ordinary
/// sync engine — unlike the local-only `KeyValue` table in
/// `core/db/app_database.dart`, rows here carry the full [SyncColumns] set
/// so they can be pushed to and pulled from the server like any other
/// syncable entity.
///
/// Phase 0 only defines the table shape; no DAO/repository reads or writes
/// it yet (that lands with the settings feature).
class Preferences extends Table with SyncColumns {
  /// Preference key, e.g. `"locale"`, `"theme_mode"`.
  TextColumn get key => text()();

  /// Preference value, stored as a raw string (JSON-encode composite
  /// values at the call site if ever needed — kept simple for Phase 0).
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {id};
}
