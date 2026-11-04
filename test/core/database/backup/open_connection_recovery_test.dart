import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/restore_journal.dart';
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
}
