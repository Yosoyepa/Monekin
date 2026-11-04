import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_restorer.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const appSchema = 15;

/// Writes a minimal Monekin-like database at [path] and returns its bytes.
Uint8List makeDb(
  String path, {
  int version = appSchema,
  List<String> attachments = const [],
  List<String> inboxPaths = const [],
}) {
  final db = sqlite3.open(path);
  db.execute(
    'CREATE TABLE appData (appDataKey TEXT PRIMARY KEY, appDataValue TEXT)',
  );
  db.execute("INSERT INTO appData VALUES ('dbVersion', '$version')");
  db.execute(
    'CREATE TABLE transactionAttachments (id TEXT PRIMARY KEY, transactionID TEXT, filePath TEXT, createdAt TEXT)',
  );
  db.execute(
    'CREATE TABLE aiInboxItems (id TEXT PRIMARY KEY, attachmentsJson TEXT)',
  );
  for (var i = 0; i < attachments.length; i++) {
    db.execute('INSERT INTO transactionAttachments VALUES (?, ?, ?, ?)', [
      'a$i',
      't$i',
      attachments[i],
      '2026-11-04',
    ]);
  }
  db.execute('INSERT INTO aiInboxItems VALUES (?, ?)', [
    'i1',
    jsonEncode(inboxPaths),
  ]);
  db.close();
  return File(path).readAsBytesSync();
}

List<String> attachmentPaths(String dbPath) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    return [
      for (final r in db.select(
        'SELECT filePath FROM transactionAttachments ORDER BY id',
      ))
        r['filePath'] as String,
    ];
  } finally {
    db.close();
  }
}

void main() {
  late Directory root;
  late String sourceDocs;
  late String targetDocs;
  late String targetDb;
  late int closed;
  late BackupRestorer restorer;

  setUp(() {
    root = Directory.systemTemp.createTempSync('backup_restorer_test');
    sourceDocs = p.join(root.path, 'source');
    targetDocs = p.join(root.path, 'target');
    Directory(
      p.join(sourceDocs, 'finanzas_ia', 'receipts'),
    ).createSync(recursive: true);
    Directory(targetDocs).createSync(recursive: true);
    targetDb = p.join(targetDocs, 'monekin.db');
    closed = 0;
    restorer = BackupRestorer(
      databasePath: () async => targetDb,
      documentsDir: () async => targetDocs,
      schemaVersion: () => appSchema,
      closeDatabase: () async => closed++,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<Uint8List> v2Backup() async {
    final photoA = p.join(sourceDocs, 'finanzas_ia', 'receipts', 'a.jpg');
    final photoB = p.join(sourceDocs, 'finanzas_ia', 'receipts', 'b.jpg');
    File(photoA).writeAsBytesSync([1, 1, 1]);
    File(photoB).writeAsBytesSync([2, 2]);
    final db = makeDb(
      p.join(root.path, 'source.db'),
      attachments: [photoA, photoB],
      inboxPaths: [photoA],
    );
    return buildBackupPackage(
      database: db,
      documentsDir: sourceDocs,
      schemaVersion: appSchema,
      date: DateTime(2026, 11, 4),
    );
  }

  test(
    'v2 copy with 2 photos restores them in another documents folder',
    () async {
      final backup = await v2Backup();
      makeDb(targetDb);

      await restorer.restore(backup);

      final receipts = p.join(targetDocs, 'finanzas_ia', 'receipts');
      expect(attachmentPaths(targetDb), [
        p.join(receipts, 'a.jpg'),
        p.join(receipts, 'b.jpg'),
      ]);
      expect(File(p.join(receipts, 'a.jpg')).readAsBytesSync(), [1, 1, 1]);
      expect(File(p.join(receipts, 'b.jpg')).readAsBytesSync(), [2, 2]);

      final db = sqlite3.open(targetDb, mode: OpenMode.readOnly);
      final inbox = db
          .select('SELECT attachmentsJson FROM aiInboxItems')
          .single;
      db.close();
      expect(jsonDecode(inbox['attachmentsJson'] as String), [
        p.join(receipts, 'a.jpg'),
      ]);

      expect(closed, 1);
      expect(File(targetDb).existsSync(), isTrue);
      expect(File('$targetDb.restore_tmp').existsSync(), isFalse);
    },
  );

  test('keeps the replaced database as a recoverable backup', () async {
    final before = makeDb(targetDb, attachments: ['/old/x.jpg']);

    await restorer.restore(await v2Backup());

    final saved = File(p.join(targetDocs, 'monekin.pre_restore_backup.db'));
    expect(saved.readAsBytesSync(), before);
  });

  test('v1 copy (bare database) still restores', () async {
    final v1 = makeDb(
      p.join(root.path, 'v1.db'),
      version: 14,
      attachments: ['/data/x.jpg'],
    );
    makeDb(targetDb);

    await restorer.restore(v1);

    expect(attachmentPaths(targetDb), ['/data/x.jpg']);
    expect(closed, 1);
  });

  test('a photo missing from the copy keeps its stored path', () async {
    final photo = p.join(sourceDocs, 'finanzas_ia', 'receipts', 'a.jpg');
    File(photo).writeAsBytesSync([1]);
    final backup = await buildBackupPackage(
      database: makeDb(
        p.join(root.path, 's.db'),
        attachments: [photo, '/gone/other.jpg'],
      ),
      documentsDir: sourceDocs,
      schemaVersion: appSchema,
      date: DateTime(2026, 11, 4),
    );

    await restorer.restore(backup);

    expect(attachmentPaths(targetDb), [
      p.join(targetDocs, 'finanzas_ia', 'receipts', 'a.jpg'),
      '/gone/other.jpg',
    ]);
  });

  group('invalid copies leave the current database intact', () {
    late Uint8List current;

    setUp(() => current = makeDb(targetDb, attachments: ['/keep.jpg']));

    Future<void> expectRejected(
      Uint8List bytes,
      InvalidBackupReason reason,
    ) async {
      await expectLater(
        restorer.restore(bytes),
        throwsA(
          isA<InvalidBackupException>().having(
            (e) => e.reason,
            'reason',
            reason,
          ),
        ),
      );
      expect(File(targetDb).readAsBytesSync(), current);
      expect(closed, 0);
      expect(File('$targetDb.restore_tmp').existsSync(), isFalse);
      expect(
        Directory(p.join(targetDocs, 'finanzas_ia')).existsSync(),
        isFalse,
      );
    }

    test('random bytes', () async {
      await expectRejected(
        Uint8List.fromList(List.generate(4096, (i) => i % 251)),
        InvalidBackupReason.corrupt,
      );
    });

    test('truncated database', () async {
      final full = makeDb(p.join(root.path, 'full.db'));
      await expectRejected(
        Uint8List.sublistView(full, 0, full.length ~/ 2),
        InvalidBackupReason.corrupt,
      );
    });

    test('truncated package', () async {
      final backup = await v2Backup();
      await expectRejected(
        Uint8List.sublistView(backup, 0, backup.length ~/ 2),
        InvalidBackupReason.corrupt,
      );
    });

    test('database without appData', () async {
      final path = p.join(root.path, 'empty.db');
      sqlite3.open(path)
        ..execute('CREATE TABLE other (x)')
        ..close();
      await expectRejected(
        File(path).readAsBytesSync(),
        InvalidBackupReason.corrupt,
      );
    });

    test('newer schema than the app', () async {
      final newer = makeDb(
        p.join(root.path, 'newer.db'),
        version: appSchema + 1,
      );
      await expectRejected(newer, InvalidBackupReason.newerSchema);
    });

    test('package of a newer format', () async {
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({'format': kBackupFormat, 'version': 9}),
          ),
        )
        ..add(ArchiveFile.bytes('database.db', current));
      await expectRejected(
        ZipEncoder().encodeBytes(archive),
        InvalidBackupReason.corrupt,
      );
    });
  });

  test('package round trip keeps manifest data and photos', () async {
    final parsed = parseBackupPackage(await v2Backup());

    expect(parsed.schemaVersion, appSchema);
    expect(parsed.sourceDocumentsDir, sourceDocs);
    expect(parsed.photos.keys.toSet(), {'a.jpg', 'b.jpg'});
  });
}
