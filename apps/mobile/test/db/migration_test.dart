// Schema migration tests. v1 -> v2 added the phase-2 sync tables; v2 -> v3
// added `milestones.progress_percent`; v3 -> v4 added the daily log tables.
// Each step must (a) create everything correctly for a brand-new install, and
// (b) upgrade an existing install of EVERY prior version without touching its
// data.
import 'package:drift/drift.dart' show Value, Variable;
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

const _dailyLogTables = AppDatabase.dailyLogTables;

Future<Set<String>> _names(AppDatabase db, String type) async {
  final rows = await db.customSelect(
    'SELECT name FROM sqlite_master WHERE type = ?',
    variables: [Variable.withString(type)],
  ).get();
  return rows.map((r) => r.data['name'] as String).toSet();
}

Future<Set<String>> _tableNames(AppDatabase db) => _names(db, 'table');

/// The partial natural-key index must allow a rule-14 tombstone next to a
/// live row but reject a second live row for the same day.
Future<void> _expectLiveRowUniqueness(AppDatabase db) async {
  final day = DateTime.utc(2026, 1, 1);
  await db.into(db.moodLogs).insert(
        MoodLogsCompanion.insert(id: const Value('m-1'), date: day, score: 3),
      );
  await db.into(db.moodLogs).insert(
        MoodLogsCompanion.insert(
          id: const Value('m-2'),
          date: day,
          score: 4,
          deletedAt: Value(DateTime.utc(2026, 1, 2)),
        ),
      );
  await expectLater(
    db.into(db.moodLogs).insert(
          MoodLogsCompanion.insert(id: const Value('m-3'), date: day, score: 5),
        ),
    throwsA(anything),
  );
}

void main() {
  test('schemaVersion is 5', () {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    expect(db.schemaVersion, 5);
  });

  test('a fresh install creates every sync table and natural-key index',
      () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    final tables = await _tableNames(db);
    for (final table in [..._phase2Tables, ..._dailyLogTables]) {
      expect(tables, contains(table));
    }
    final indexes = await _names(db, 'index');
    expect(indexes, contains('ux_habit_logs_natural_key'));
    for (final table in _dailyLogTables) {
      expect(indexes, contains('ux_${table}_natural_key'));
    }
    await _expectLiveRowUniqueness(db);
    await db.close();
  });

  test('upgrading from schema v1 adds every later table and keeps data',
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

    for (final table in [..._phase2Tables, ..._dailyLogTables]) {
      expect(names, contains(table), reason: '$table must exist after upgrade');
    }

    final marker = await (db.select(
      db.keyValue,
    )..where((t) => t.key.equals('marker')))
        .getSingle();
    expect(marker.value, 'kept-across-migration');

    await db.close();
  });

  test(
      'upgrading from schema v2 adds milestones.progress_percent and keeps data',
      () async {
    // A realistic v2 database: the phase-2 tables as they were *before*
    // `progress_percent` existed on `milestones`, with one row in it.
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE milestones (
        id TEXT NOT NULL,
        user_id TEXT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        server_version INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 1 CHECK (dirty IN (0, 1)),
        goal_id TEXT NOT NULL,
        title TEXT NOT NULL,
        target_date TEXT NULL,
        completed_at TEXT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id)
      );
    ''');
    raw.execute(
      'INSERT INTO milestones (id, created_at, updated_at, server_version, '
      'dirty, goal_id, title, sort_order) VALUES '
      "('m-1', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
      "0, 1, 'g-1', 'kept-across-v3', 0)",
    );
    // `habit_logs` as it was in v2: WITH the table-level UNIQUE on the
    // natural key that v3 replaces with a partial index.
    raw.execute('''
      CREATE TABLE habit_logs (
        id TEXT NOT NULL,
        user_id TEXT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        server_version INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 1 CHECK (dirty IN (0, 1)),
        habit_id TEXT NOT NULL,
        date TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 1,
        value REAL NULL,
        note TEXT NULL,
        PRIMARY KEY (id),
        UNIQUE (user_id, habit_id, date)
      );
    ''');
    raw.execute(
      'INSERT INTO habit_logs (id, created_at, updated_at, server_version, '
      'dirty, habit_id, date, count) VALUES '
      "('hl-1', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
      "0, 1, 'h-1', '2026-01-01T00:00:00.000Z', 3)",
    );

    raw.execute('PRAGMA user_version = 2');

    final db = AppDatabase.withExecutor(
      NativeDatabase.opened(raw, enableMigrations: true),
    );

    // The upgrade must add the column with its default, not drop the row.
    final row = await (db.select(db.milestones)
          ..where((m) => m.id.equals('m-1')))
        .getSingle();
    expect(row.title, 'kept-across-v3');
    expect(row.progressPercent, 0,
        reason: 'the new column must default to 0 for pre-existing rows');

    // habit_logs data survives the table rebuild that drops the old UNIQUE.
    final log = await (db.select(db.habitLogs)
          ..where((l) => l.id.equals('hl-1')))
        .getSingle();
    expect(log.count, 3, reason: 'rows must be copied across the rebuild');

    // The v2 table-level UNIQUE is gone: a soft-deleted row may now share a
    // live row's natural key, which is what conflict-matrix rule 14 needs.
    await db.into(db.habitLogs).insert(
          HabitLogsCompanion.insert(
            id: const Value('hl-2'),
            habitId: 'h-1',
            date: DateTime.utc(2026, 1, 1),
            deletedAt: Value(DateTime.utc(2026, 1, 2)),
          ),
        );
    final both = await (db.select(db.habitLogs)
          ..where((l) => l.habitId.equals('h-1')))
        .get();
    expect(both, hasLength(2),
        reason: 'a rule-14 tombstone must be storable alongside the live row');

    // The partial index still forbids TWO LIVE rows on the same natural key.
    await expectLater(
      db.into(db.habitLogs).insert(
            HabitLogsCompanion.insert(
              id: const Value('hl-3'),
              habitId: 'h-1',
              date: DateTime.utc(2026, 1, 1),
            ),
          ),
      throwsA(anything),
    );

    await db.close();
  });

  test('upgrading from schema v3 adds the daily log tables and keeps data',
      () async {
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE key_value (
        "key" TEXT NOT NULL,
        value TEXT NOT NULL,
        PRIMARY KEY ("key")
      );
    ''');
    raw.execute(
      "INSERT INTO key_value (\"key\", value) VALUES ('marker', 'kept-across-v4')",
    );
    raw.execute('PRAGMA user_version = 3');

    final db = AppDatabase.withExecutor(
      NativeDatabase.opened(raw, enableMigrations: true),
    );

    final tables = await _tableNames(db);
    for (final table in _dailyLogTables) {
      expect(tables, contains(table), reason: '$table must exist after v4');
    }
    final marker = await (db.select(db.keyValue)
          ..where((t) => t.key.equals('marker')))
        .getSingle();
    expect(marker.value, 'kept-across-v4');
    await _expectLiveRowUniqueness(db);

    await db.close();
  });
}
