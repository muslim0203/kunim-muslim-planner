// Schema migration tests: `AppDatabase.schemaVersion` was bumped 1 -> 2 to
// add the phase-2 sync tables. This must (a) create everything correctly
// for a brand-new install, and (b) upgrade an existing v1 install without
// touching its existing data.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _phase2Tables = [
  'task_categories',
  'tasks',
  'calendar_events',
  'habits',
  'habit_logs',
  'goals',
  'milestones',
];

Future<Set<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((r) => r.data['name'] as String).toSet();
}

void main() {
  test('schemaVersion is 2', () {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    expect(db.schemaVersion, 2);
  });

  test('a fresh install creates all phase-2 tables', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    final names = await _tableNames(db);
    for (final table in _phase2Tables) {
      expect(names, contains(table));
    }
    await db.close();
  });

  test('upgrading from schema v1 adds phase-2 tables and keeps existing data',
      () async {
    // Hand-build a minimal "v1" database: just the `key_value` table that
    // existed before this migration, with one row already in it, and
    // PRAGMA user_version = 1 so drift's migrator takes the onUpgrade path
    // instead of onCreate.
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE key_value (
        "key" TEXT NOT NULL,
        value TEXT NOT NULL,
        PRIMARY KEY ("key")
      );
    ''');
    raw.execute(
      "INSERT INTO key_value (\"key\", value) VALUES ('marker', 'kept-across-migration')",
    );
    raw.execute('PRAGMA user_version = 1');

    final db = AppDatabase.withExecutor(
      NativeDatabase.opened(raw, enableMigrations: true),
    );

    // Force the connection (and therefore the migration) to run.
    final names = await _tableNames(db);

    for (final table in _phase2Tables) {
      expect(names, contains(table), reason: '$table must exist after upgrade');
    }

    final marker = await (db.select(
      db.keyValue,
    )..where((t) => t.key.equals('marker')))
        .getSingle();
    expect(marker.value, 'kept-across-migration');

    await db.close();
  });
}
