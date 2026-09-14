import 'package:drift/drift.dart';

import 'sync_column_mixin.dart';

/// Time spent with family on one local day: the `family_logs` entity.
/// Feature-owned by `features/family/`.
///
/// - Natural key `(user_id, coalesce(ref_id, ''), date)`; [refId] is always
///   null today.
/// - Server merge: [minutes] max-wins (additive), [activities] set union,
///   [note] last-write-wins.
///
/// Live-row uniqueness is the partial index `ux_family_logs_natural_key`.
class FamilyLogs extends Table with SyncColumns {
  TextColumn get refId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  IntColumn get minutes => integer().nullable()();

  /// JSON array of activity codes, e.g. `["meal","walk"]`. Synced as a list.
  TextColumn get activities => text().withDefault(const Constant('[]'))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
