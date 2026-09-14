/// Which account this device's data belongs to.
///
/// The device holds one account's data at a time. Signing in records the
/// account in the local-only `key_value` table and adopts every row that
/// has no owner yet; from then on the `stamp_user_id_*` triggers
/// (`AppDatabase`) stamp new rows as they are inserted. Rows then look
/// exactly like the same account's rows pulled from the server, so the
/// natural-key indexes (`COALESCE(user_id, '')`) and the server's
/// `foreign_user` check agree with the local data.
library;

import 'package:drift/drift.dart';

import '../db/app_database.dart';

class LocalAccount {
  const LocalAccount({required this.userId, required this.email});

  final String userId;
  final String email;
}

class LocalAccountStore {
  LocalAccountStore(this.db);

  final AppDatabase db;

  static const String userIdKey = AppDatabase.accountUserIdKey;
  static const String emailKey = 'auth.email';

  Future<LocalAccount?> read() async {
    final query = db.select(db.keyValue)
      ..where((row) => row.key.isIn(const [userIdKey, emailKey]));
    final byKey = {for (final row in await query.get()) row.key: row.value};
    final userId = byKey[userIdKey];
    final email = byKey[emailKey];
    if (userId == null || email == null) return null;
    return LocalAccount(userId: userId, email: email);
  }

  /// Records the signed-in account and gives it every unowned row.
  ///
  /// A direct update, not a sync write: the server sets `user_id` from the
  /// token anyway, so nothing needs to be re-sent. `OR IGNORE` leaves a row
  /// alone if it would collide with a live row of the same natural key.
  Future<void> adopt({required String userId, required String email}) {
    return db.transaction(() async {
      await _put(userIdKey, userId);
      await _put(emailKey, email);
      final tables = db.allTables
          .where(
            (table) => AppDatabase.syncTables.contains(table.actualTableName),
          )
          .toSet();
      for (final table in AppDatabase.syncTables) {
        await db.customUpdate(
          'UPDATE OR IGNORE "$table" SET user_id = ? WHERE user_id IS NULL',
          variables: [Variable.withString(userId)],
          updates: tables,
          updateKind: UpdateKind.update,
        );
      }
    });
  }

  /// Forgets the account. Its rows stay on the device.
  Future<void> release() {
    return (db.delete(db.keyValue)
          ..where((row) => row.key.isIn(const [userIdKey, emailKey])))
        .go();
  }

  Future<void> _put(String key, String value) {
    return db.into(db.keyValue).insertOnConflictUpdate(
          KeyValueCompanion.insert(key: key, value: value),
        );
  }
}
