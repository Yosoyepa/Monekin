import 'dart:io';

import 'package:drift/drift.dart'
    show OpeningDetails, QueryExecutor, QueryExecutorUser;
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/restore_journal.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documents);
  final String documents;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;
}

/// Opens a bare connection without the app schema.
class _User implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String dbPath;
  late PathProviderPlatform previous;

  setUp(() {
    root = Directory.systemTemp.createTempSync('open_connection_recovery');
    dbPath = p.join(root.path, 'test.db');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDown(() {
    isBackgroundIsolate = false;
    PathProviderPlatform.instance = previous;
    root.deleteSync(recursive: true);
  });

  test(
    'opening the database undoes a restore the app did not finish',
    () async {
      final db = sqlite3.open(dbPath);
      db.execute('CREATE TABLE t (v TEXT)');
      db.execute("INSERT INTO t VALUES ('original')");
      db.close();
      final original = File(dbPath).readAsBytesSync();
      final photo = p.join(root.path, 'receipts', 'b.jpg');

      // The state a restore leaves if the app dies after the swap.
      final journal = RestoreJournal(dbPath);
      await journal.begin(hadDatabase: true, photos: [photo]);
      File(photo)
        ..createSync(recursive: true)
        ..writeAsBytesSync([9]);
      await journal.moveLiveAside();
      File(dbPath).writeAsBytesSync([42, 42]);

      final executor = await openConnection('test.db').opener();
      await executor.close();

      expect(File(dbPath).readAsBytesSync(), original);
      expect(File(photo).existsSync(), isFalse);
      expect(journal.isOpen, isFalse);
    },
  );

  test('without a journal the database opens untouched', () async {
    sqlite3.open(dbPath)
      ..execute('CREATE TABLE t (v TEXT)')
      ..close();
    final before = File(dbPath).readAsBytesSync();

    final executor = await openConnection('test.db').opener();
    await executor.close();

    expect(File(dbPath).readAsBytesSync(), before);
  });

  test('with a restore alive the database is not opened', () async {
    sqlite3.open(dbPath)
      ..execute('CREATE TABLE t (v TEXT)')
      ..close();
    final before = File(dbPath).readAsBytesSync();
    final marker = File('$dbPath$kRestoreMarkerSuffix')
      ..writeAsStringSync('{}');
    final lock = (await RestoreLock.tryAcquire(dbPath))!;

    await expectLater(
      openConnection(
        'test.db',
        recoveryWait: const Duration(milliseconds: 200),
      ).opener(),
      throwsA(isA<RestoreBusyException>()),
    );

    expect(marker.existsSync(), isTrue, reason: 'its marker is not touched');
    expect(File(dbPath).readAsBytesSync(), before);
    await lock.release();
  });

  test('the background isolate leaves a restore marker untouched', () async {
    sqlite3.open(dbPath)
      ..execute('CREATE TABLE t (v TEXT)')
      ..close();
    final marker = File('$dbPath$kRestoreMarkerSuffix')
      ..writeAsStringSync('{}');
    isBackgroundIsolate = true;

    await expectLater(
      openConnection('test.db').opener(),
      throwsA(isA<RestoreBusyException>()),
    );

    expect(marker.existsSync(), isTrue, reason: 'no recovery from there');
  });

  test('the background isolate creates no database over a set-aside one', () {
    File('$dbPath$kRestoreAsideSuffix').writeAsBytesSync([1]);
    isBackgroundIsolate = true;

    expect(
      openConnection('test.db').opener(),
      throwsA(isA<RestoreBusyException>()),
    );
    expect(File(dbPath).existsSync(), isFalse);
  });

  test('the background isolate opens a healthy database as usual', () async {
    sqlite3.open(dbPath)
      ..execute('CREATE TABLE t (v TEXT)')
      ..close();
    isBackgroundIsolate = true;

    final executor = await openConnection('test.db').opener();
    await executor.close();
  });

  test('the app connection waits for another writer', () async {
    sqlite3.open(dbPath)
      ..execute('CREATE TABLE t (v TEXT)')
      ..close();

    // The setup runs in the isolate drift starts for the connection.
    final executor = await openConnection('test.db').opener();
    await executor.ensureOpen(_User());
    final rows = await executor.runSelect('PRAGMA busy_timeout', []);
    await executor.close();

    expect(rows.single.values.single, 5000);
  });

  test('a recovery that holds the lock only a moment is waited for', () async {
    sqlite3.open(dbPath)
      ..execute('CREATE TABLE t (v TEXT)')
      ..close();
    final lock = (await RestoreLock.tryAcquire(dbPath))!;
    Future<void>.delayed(const Duration(milliseconds: 300), lock.release);

    final executor = await openConnection('test.db').opener();
    await executor.close();
  });

  test(
    'with no database but the one a restore set aside, it opens that',
    () async {
      final db = sqlite3.open(dbPath);
      db.execute('CREATE TABLE t (v TEXT)');
      db.execute("INSERT INTO t VALUES ('original')");
      db.close();
      File(dbPath).renameSync('$dbPath$kRestoreAsideSuffix');

      final executor = await openConnection('test.db').opener();
      await executor.close();

      final reopened = sqlite3.open(dbPath, mode: OpenMode.readOnly);
      expect(reopened.select('SELECT v FROM t').single['v'], 'original');
      reopened.close();
    },
  );
}
