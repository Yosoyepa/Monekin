import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/backup_database_service.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_restorer.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../../features_ia/google/backup_crypto_test.dart' show testParams;

class _TestDatabase extends AppDB {
  _TestDatabase(this.file) : super.forTesting(NativeDatabase(file));
  final File file;

  @override
  Future<String> get databasePath async => file.path;
}

List<String> appDataOf(String path) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return [
      for (final row in db.select(
        'SELECT appDataKey, appDataValue FROM appData ORDER BY appDataKey',
      ))
        '${row['appDataKey']}=${row['appDataValue']}',
    ];
  } finally {
    db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late _TestDatabase db;
  late BackupDatabaseService service;
  late BackupKey key;
  late Directory exports;
  late String documents;

  setUpAll(() async {
    key = await createBackupKey('a long enough password', params: testParams);
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('local_encrypted_backup_test');
    documents = p.join(root.path, 'documents');
    exports = Directory(p.join(root.path, 'exports'))..createSync();
    Directory(receiptsDirOf(documents)).createSync(recursive: true);

    db = _TestDatabase(File(p.join(root.path, 'monekin.db')));
    await db.customSelect('SELECT 1').get();
    await db.close();
    final raw = sqlite3.open(p.join(root.path, 'monekin.db'));
    raw.execute(
      "INSERT OR REPLACE INTO appData VALUES ('dbVersion', '${db.schemaVersion}')",
    );
    raw.close();
    service = BackupDatabaseService()..db = db;
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'the export is a sealed .fia file with the database and photos',
    () async {
      final big = Uint8List.fromList(
        List.generate(3 * 1024 * 1024 + 700, (i) => Random(i).nextInt(256)),
      );
      File(p.join(receiptsDirOf(documents), 'big.jpg')).writeAsBytesSync(big);

      final file = await service.exportEncryptedBackup(
        exports.path,
        key,
        documentsDir: documents,
      );

      expect(p.extension(file.path), '.fia');
      final sealed = file.readAsBytesSync();
      expect(isEncryptedBackup(sealed), isTrue);
      expect(looksLikeBackupZip(sealed), isFalse);

      final package = parseBackupPackage(
        await decryptBackupBytes(sealed, resolverFromKey(key)),
      );
      final copy = File(p.join(root.path, 'copy.db'))
        ..writeAsBytesSync(package.database);
      expect(
        appDataOf(copy.path),
        appDataOf(p.join(root.path, 'monekin.db')),
        reason: 'the snapshot holds what the live database holds',
      );
      expect(package.photos['big.jpg'], big);
      expect(package.schemaVersion, db.schemaVersion);
    },
  );

  test(
    'the exported file restores with its password, and not with another',
    () async {
      final file = await service.exportEncryptedBackup(
        exports.path,
        key,
        documentsDir: documents,
      );
      final sealed = file.readAsBytesSync();

      final target = File(p.join(root.path, 'restored', 'monekin.db'))
        ..createSync(recursive: true);
      target.writeAsBytesSync([0, 1, 2]);
      BackupRestorer restorer() => BackupRestorer(
        databasePath: () async => target.path,
        documentsDir: () async => p.join(root.path, 'restored_docs'),
        schemaVersion: () => db.schemaVersion,
        closeDatabase: () async {},
      );

      await expectLater(
        restorer().restore(
          sealed,
          resolveKey: resolverFromPassword('another password'),
        ),
        throwsA(
          isA<InvalidBackupException>().having(
            (e) => e.reason,
            'reason',
            InvalidBackupReason.wrongPassword,
          ),
        ),
      );
      expect(target.readAsBytesSync(), [0, 1, 2]);

      await restorer().restore(
        sealed,
        resolveKey: resolverFromPassword('a long enough password'),
      );
      expect(
        appDataOf(target.path),
        appDataOf(p.join(root.path, 'monekin.db')),
      );
    },
  );
}
