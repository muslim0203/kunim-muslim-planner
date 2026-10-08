/// Opens the bundled Qur'an database.
///
/// SQLite cannot read out of the asset bundle, so the file is copied to the
/// app's support directory once and opened read-only from there. The copy is
/// refreshed whenever the bundled asset's size changes — that is what a new
/// build of the database looks like from here, and re-copying 1.7 MB is
/// cheaper than shipping a stale Qur'an.
///
/// Read-only is not a detail: the text must be exactly what
/// `packages/content_tools/build_quran_db.py` put there, so the app is not
/// even able to write to it.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const String quranAssetPath = 'assets/db/quran.sqlite';

class QuranAssetDatabase {
  QuranAssetDatabase({this.fileName = 'quran.sqlite'}) : _path = null;

  /// Opens a database file straight from disk, without the asset bundle or a
  /// support directory. Tests use it to read the very file the app ships.
  QuranAssetDatabase.fromFile(String path)
      : _path = path,
        fileName = path;

  final String fileName;
  final String? _path;
  Database? _db;

  /// The open database, copying the asset out on the first call.
  Future<Database> open() async {
    final existing = _db;
    if (existing != null) return existing;

    final direct = _path;
    if (direct != null) {
      return _db = sqlite3.open(direct, mode: OpenMode.readOnly);
    }

    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    final asset = await rootBundle.load(quranAssetPath);
    final bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );

    if (!file.existsSync() || file.lengthSync() != bytes.length) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    return _db = sqlite3.open(file.path, mode: OpenMode.readOnly);
  }

  void close() {
    _db?.dispose();
    _db = null;
  }
}

final quranAssetDatabaseProvider = Provider<QuranAssetDatabase>((ref) {
  final database = QuranAssetDatabase();
  ref.onDispose(database.close);
  return database;
});
