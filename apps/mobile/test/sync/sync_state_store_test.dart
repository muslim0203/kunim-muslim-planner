// `SyncStateStore` holds the pull cursor and device id needed by the (not
// yet built, T-204) sync engine, on top of the existing local-only
// `KeyValue` table — never the synced `Preferences` table (ADR-0002 §3).
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/outbox.dart';

void main() {
  late AppDatabase db;
  late SyncStateStore store;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = SyncStateStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('a brand-new device starts at cursor 0', () async {
    expect(await store.getCursor(), 0);
  });

  test('cursor round-trips', () async {
    await store.setCursor(10428);
    expect(await store.getCursor(), 10428);

    await store.setCursor(10430);
    expect(await store.getCursor(), 10430);
  });

  test('device id is null until set, then round-trips', () async {
    expect(await store.getDeviceId(), isNull);

    await store.setDeviceId('9f0e1a2b-0000-4000-8000-000000000000');
    expect(
      await store.getDeviceId(),
      '9f0e1a2b-0000-4000-8000-000000000000',
    );
  });

  test('cursor and device id are independent of each other', () async {
    await store.setDeviceId('device-1');
    await store.setCursor(5);

    expect(await store.getDeviceId(), 'device-1');
    expect(await store.getCursor(), 5);
  });
}
