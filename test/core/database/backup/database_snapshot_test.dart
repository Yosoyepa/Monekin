import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/backup_database_service.dart';
import 'package:monekin/core/database/backup/database_snapshot.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _TestDatabase extends AppDB {
  _TestDatabase(this.file) : super.forTesting(NativeDatabase(file));
  final File file;

  @override
  Future<String> get databasePath async => file.path;
}

int rowsIn(String path, String table) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;
  } finally {
    db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('db_snapshot_test'));
  tearDown(() => root.deleteSync(recursive: true));

  group('a committed write that is still in the WAL', () {
    late String live;
    late Database connection;

    setUp(() {
      live = p.join(root.path, 'live.db');
      connection = sqlite3.open(live);
      connection.execute('PRAGMA journal_mode = WAL');
      connection.execute('CREATE TABLE t (id INTEGER)');
      connection.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      connection.execute('INSERT INTO t VALUES (1)');
    });

    tearDown(() => connection.close());

    test('is missed when the database file is copied directly', () {
      final copy = p.join(root.path, 'raw.db');
      File(live).copySync(copy);

      expect(File('$live-wal').lengthSync(), greaterThan(0));
      expect(rowsIn(copy, 't'), 0);
    });

    test('is in the VACUUM INTO snapshot', () async {
      final snapshot = p.join(root.path, 'snapshot.db');

      await snapshotDatabase(live, snapshot);

      expect(rowsIn(snapshot, 't'), 1);
      expect(File('$snapshot-wal').existsSync(), isFalse);
    });

    test('replaces an earlier snapshot at the same path', () async {
      final snapshot = p.join(root.path, 'snapshot.db');
      await snapshotDatabase(live, snapshot);
      connection.execute('INSERT INTO t VALUES (2)');

      await snapshotDatabase(live, snapshot);

      expect(rowsIn(snapshot, 't'), 2);
    });
  });

  test('a missing database is reported, not created', () {
    final missing = p.join(root.path, 'missing.db');

    expect(
      () => snapshotDatabaseSync(missing, p.join(root.path, 'out.db')),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(missing).existsSync(), isFalse);
  });

  test('the service reads the snapshot, not the file', () async {
    final file = File(p.join(root.path, 'monekin.db'));
    final db = _TestDatabase(file);
    addTearDown(db.close);
    await db.customStatement('PRAGMA journal_mode = WAL');
    await db.customSelect('SELECT 1').get();
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await db.customStatement(
      "INSERT INTO appData VALUES ('dbVersion', '${db.schemaVersion}')",
    );
    final service = BackupDatabaseService()..db = db;

    final raw = File(p.join(root.path, 'raw.db'));
    file.copySync(raw.path);
    expect(rowsIn(raw.path, 'appData'), 0, reason: 'the file alone misses it');

    final copy = File(p.join(root.path, 'copy.db'))
      ..writeAsBytesSync(await service.getDbFileInBytes());

    expect(rowsIn(copy.path, 'appData'), 1);
    expect(File('${file.path}$kSnapshotSuffix').existsSync(), isFalse);
  });
}
