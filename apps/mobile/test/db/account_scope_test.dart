// Local rows and the signed-in account: adoption on sign-in, stamping of new
// rows by trigger, and day queries that see rows pulled for the account.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/auth/local_account_store.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/features/habits/domain/local_day.dart';
import 'package:kunim/features/mood/data/mood_log_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _user = '11111111-1111-4111-8111-111111111111';
const _day = LocalDay(2026, 9, 14);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() => db.close());

  MoodLogRepository mood() => MoodLogRepository(db, onLocalWrite: () {});

  Future<String?> ownerOf(String id) async =>
      (await (db.select(db.moodLogs)..where((l) => l.id.equals(id)))
              .getSingle())
          .userId;

  test('signed out, new rows have no owner', () async {
    final row = await mood().saveForDay(_day, score: 3);

    expect(await ownerOf(row.id), isNull);
  });

  test('signing in adopts existing rows and stamps new ones', () async {
    final before = await mood().saveForDay(_day, score: 3);

    await LocalAccountStore(db).adopt(userId: _user, email: 'a@b.co');

    expect(await ownerOf(before.id), _user);
    final later = await mood().saveForDay(_day.addDays(1), score: 4);
    expect(await ownerOf(later.id), _user);
    // Editing the day still finds the adopted row.
    expect((await mood().saveForDay(_day, score: 5)).id, before.id);
    expect((await LocalAccountStore(db).read())?.email, 'a@b.co');
  });

  test('rows pulled for the account show up in day queries', () async {
    await db.into(db.moodLogs).insert(
          MoodLogsCompanion.insert(
            id: const Value('pulled'),
            userId: const Value(_user),
            date: _day.toUtcMidnight(),
            score: 4,
            dirty: const Value(false),
          ),
        );

    expect((await mood().watchForDay(_day).first)?.id, 'pulled');
    expect(await mood().watchRecent().first, hasLength(1));
  });

  test('signing out stops stamping and keeps the rows', () async {
    await LocalAccountStore(db).adopt(userId: _user, email: 'a@b.co');
    final owned = await mood().saveForDay(_day, score: 3);

    await LocalAccountStore(db).release();
    final unowned = await mood().saveForDay(_day.addDays(1), score: 4);

    expect(await LocalAccountStore(db).read(), isNull);
    expect(await ownerOf(owned.id), _user);
    expect(await ownerOf(unowned.id), isNull);
  });

  test('upgrading from schema v4 installs the stamping triggers', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    final current = AppDatabase.withExecutor(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await current.customSelect('SELECT 1').get();
    for (final table in AppDatabase.syncTables) {
      raw.execute('DROP TRIGGER stamp_user_id_$table');
    }
    // Version 4 had no prayer_logs either.
    raw.execute('DROP TABLE prayer_logs');
    raw.execute('PRAGMA user_version = 4');
    await current.close();

    final upgraded = AppDatabase.withExecutor(
      NativeDatabase.opened(raw),
    );
    final rows = await upgraded
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        .get();
    final names = rows.map((row) => row.data['name'] as String).toSet();

    expect(upgraded.schemaVersion, 6);
    for (final table in AppDatabase.syncTables) {
      expect(names, contains('stamp_user_id_$table'));
    }
    await upgraded.close();
  });
}
