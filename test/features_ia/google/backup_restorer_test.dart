import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:monekin/core/database/backup/restore_journal.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_restorer.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'backup_crypto_test.dart' show testParams;

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
  db.execute('CREATE TABLE accounts (id TEXT)');
  db.execute('CREATE TABLE transactions (id TEXT)');
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

extension on BackupRestorer {
  /// Restores a copy that is not encrypted, as if the user had confirmed it.
  Future<void> restorePlain(Uint8List bytes) =>
      restore(bytes, unencryptedConfirmed: true);
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

      await restorer.restorePlain(backup);

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

    await restorer.restorePlain(await v2Backup());

    final saved = preCopyFiles(targetDb, kPreRestoreCopyKind).single;
    expect(attachmentPaths(saved.path), ['/old/x.jpg']);
    expect(before, isNotEmpty);
  });

  test('v1 copy (bare database) still restores', () async {
    final v1 = makeDb(
      p.join(root.path, 'v1.db'),
      version: 14,
      attachments: ['/data/x.jpg'],
    );
    makeDb(targetDb);

    await restorer.restorePlain(v1);

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

    await restorer.restorePlain(backup);

    expect(attachmentPaths(targetDb), [
      p.join(targetDocs, 'finanzas_ia', 'receipts', 'a.jpg'),
      '/gone/other.jpg',
    ]);
  });

  group('v3 encrypted copies', () {
    const password = 'a long enough password';
    late BackupKey key;
    late Uint8List sealed;
    late Uint8List current;

    setUpAll(() async {
      key = await createBackupKey(password, params: testParams);
    });

    setUp(() async {
      sealed = await encryptBackupBytes(await v2Backup(), key, blockSize: 4096);
      current = makeDb(targetDb, attachments: ['/keep.jpg']);
    });

    Future<void> expectUntouched(
      Future<void> Function() attempt,
      InvalidBackupReason reason,
    ) async {
      await expectLater(
        attempt(),
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

    test('restores with the password of its header', () async {
      await restorer.restore(
        sealed,
        resolveKey: resolverFromPassword(password),
      );

      final receipts = p.join(targetDocs, 'finanzas_ia', 'receipts');
      expect(attachmentPaths(targetDb), [
        p.join(receipts, 'a.jpg'),
        p.join(receipts, 'b.jpg'),
      ]);
      expect(File(p.join(receipts, 'a.jpg')).readAsBytesSync(), [1, 1, 1]);
      expect(closed, 1);
    });

    test('restores with the stored key', () async {
      await restorer.restore(sealed, resolveKey: resolverFromKey(key));
      expect(closed, 1);
    });

    test(
      'a wrong password changes nothing',
      () => expectUntouched(
        () => restorer.restore(
          sealed,
          resolveKey: resolverFromPassword('not the password'),
        ),
        InvalidBackupReason.wrongPassword,
      ),
    );

    test('a changed byte changes nothing', () {
      final changed = Uint8List.fromList(sealed)..[sealed.length - 40] ^= 1;
      return expectUntouched(
        () => restorer.restore(changed, resolveKey: resolverFromKey(key)),
        InvalidBackupReason.tampered,
      );
    });

    test('a truncated copy changes nothing', () {
      final cut = sealed.sublist(0, sealed.length - 20);
      return expectUntouched(
        () => restorer.restore(cut, resolveKey: resolverFromKey(key)),
        InvalidBackupReason.tampered,
      );
    });

    test(
      'without a way to open it, it asks for the password',
      () => expectUntouched(
        () => restorer.restore(sealed),
        InvalidBackupReason.passwordRequired,
      ),
    );
  });

  group('invalid copies leave the current database intact', () {
    late Uint8List current;

    setUp(() => current = makeDb(targetDb, attachments: ['/keep.jpg']));

    Future<void> expectRejected(
      Uint8List bytes,
      InvalidBackupReason reason,
    ) async {
      await expectLater(
        restorer.restorePlain(bytes),
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

  group('a restore that fails halfway changes nothing', () {
    late String receipts;

    setUp(() {
      receipts = p.join(targetDocs, 'finanzas_ia', 'receipts');
      Directory(receipts).createSync(recursive: true);
    });

    BackupRestorer failingAtClose() => BackupRestorer(
      databasePath: () async => targetDb,
      documentsDir: () async => targetDocs,
      schemaVersion: () => appSchema,
      closeDatabase: () async => throw const FileSystemException('locked'),
    );

    test(
      'a failure when closing leaves the journal and the start undoes it',
      () async {
        final before = makeDb(targetDb, attachments: ['/keep.jpg']);
        final kept = File(p.join(receipts, 'a.jpg'))..writeAsBytesSync([7, 7]);
        final backup = await v2Backup();

        await expectLater(
          failingAtClose().restorePlain(backup),
          throwsA(
            isA<RestoreNeedsRestartException>().having(
              (e) => e.cause,
              'cause',
              isA<FileSystemException>(),
            ),
          ),
        );
        expect(RestoreJournal(targetDb).isOpen, isTrue);

        expect(await RestoreJournal.recoverInterrupted(targetDb), isTrue);

        expect(File(targetDb).readAsBytesSync(), before);
        expect(kept.readAsBytesSync(), [7, 7], reason: 'not overwritten');
        expect(
          File(p.join(receipts, 'b.jpg')).existsSync(),
          isFalse,
          reason: 'the photo brought before the failure is removed',
        );
        expect(File('$targetDb.restore_tmp').existsSync(), isFalse);
        expect(Directory('$targetDb.restore_photos').existsSync(), isFalse);
      },
    );
    test('a photo already in the folder is not overwritten', () async {
      makeDb(targetDb);
      final kept = File(p.join(receipts, 'a.jpg'))..writeAsBytesSync([7, 7]);

      await restorer.restorePlain(await v2Backup());

      expect(kept.readAsBytesSync(), [7, 7]);
      expect(File(p.join(receipts, 'b.jpg')).readAsBytesSync(), [2, 2]);
      expect(Directory('$targetDb.restore_photos').existsSync(), isFalse);
    });

    test('a database without the transactions table is rejected', () async {
      final before = makeDb(targetDb);
      final path = p.join(root.path, 'no_tx.db');
      sqlite3.open(path)
        ..execute('CREATE TABLE appData (appDataKey TEXT, appDataValue TEXT)')
        ..execute("INSERT INTO appData VALUES ('dbVersion', '$appSchema')")
        ..execute('CREATE TABLE accounts (id TEXT)')
        ..close();

      await expectLater(
        restorer.restorePlain(File(path).readAsBytesSync()),
        throwsA(isA<InvalidBackupException>()),
      );

      expect(File(targetDb).readAsBytesSync(), before);
      expect(closed, 0);
    });
  });

  test(
    'keeps the replaced database as a copy that cleanup will time',
    () async {
      makeDb(targetDb);
      final stateFile = File(p.join(root.path, 'pre_copies.json'));
      final withState = BackupRestorer(
        databasePath: () async => targetDb,
        documentsDir: () async => targetDocs,
        schemaVersion: () => appSchema,
        closeDatabase: () async => closed++,
        preCopies: PreCopiesState(() async => stateFile),
        now: () => DateTime(2026, 11, 4),
      );

      await withState.restorePlain(await v2Backup());

      expect(stateFile.existsSync(), isTrue);
      expect(preCopyFiles(targetDb, kPreRestoreCopyKind), hasLength(1));
    },
  );

  group('a copy that is not encrypted', () {
    test('is refused until the user confirms, touching nothing', () async {
      final before = makeDb(targetDb);
      final stages = <RestoreStage>[];
      final guarded = BackupRestorer(
        databasePath: () async => targetDb,
        documentsDir: () async => targetDocs,
        schemaVersion: () => appSchema,
        closeDatabase: () async => closed++,
        onStage: stages.add,
      );

      for (final bytes in [
        await v2Backup(),
        makeDb(p.join(root.path, 'v1.db')),
      ]) {
        await expectLater(
          guarded.restore(bytes),
          throwsA(
            isA<InvalidBackupException>().having(
              (e) => e.reason,
              'reason',
              InvalidBackupReason.unencrypted,
            ),
          ),
        );
      }

      expect(stages, isEmpty);
      expect(closed, 0);
      expect(File(targetDb).readAsBytesSync(), before);
    });

    test('a bare v1 database goes through both phases', () async {
      final v1 = makeDb(
        p.join(root.path, 'v1.db'),
        version: 14,
        attachments: ['/data/x.jpg'],
      );
      final before = makeDb(targetDb, attachments: ['/old.jpg']);
      final stages = <RestoreStage>[];
      late Uint8List atClose;
      late bool stagedAtClose;
      final twoPhase = BackupRestorer(
        databasePath: () async => targetDb,
        documentsDir: () async => targetDocs,
        schemaVersion: () => appSchema,
        closeDatabase: () async {
          atClose = File(targetDb).readAsBytesSync();
          stagedAtClose = File('$targetDb.restore_tmp').existsSync();
        },
        onStage: stages.add,
      );

      await twoPhase.restore(v1, unencryptedConfirmed: true);

      expect(stages, RestoreStage.values);
      expect(atClose, before, reason: 'the open database was not overwritten');
      expect(stagedAtClose, isTrue, reason: 'the new one was ready beside it');
      expect(attachmentPaths(targetDb), ['/data/x.jpg']);
    });
  });

  group('a restore that fails in any stage goes back', () {
    late String receipts;
    late Uint8List before;
    const sidecars = {
      '-wal': [1, 2, 3],
      '-shm': [4, 5],
      '-journal': [6],
    };

    setUp(() {
      receipts = p.join(targetDocs, 'finanzas_ia', 'receipts');
      Directory(receipts).createSync(recursive: true);
      before = makeDb(targetDb, attachments: ['/keep.jpg']);
    });

    BackupRestorer failingAt(RestoreStage stage) => BackupRestorer(
      databasePath: () async => targetDb,
      documentsDir: () async => targetDocs,
      schemaVersion: () => appSchema,
      closeDatabase: () async => closed++,
      now: () => DateTime(2026, 11, 4),
      onStage: (s) {
        if (s == stage) throw StateError('failure at ${s.name}');
      },
    );

    void expectNoLeftovers() {
      for (final suffix in const [
        '.restore_marker',
        '.restore_marker.new',
        '.restore_tmp',
        '.restore_photos',
        '.restore_bak',
        '-wal.restore_bak',
        '-shm.restore_bak',
        '-journal.restore_bak',
      ]) {
        expect(
          FileSystemEntity.typeSync('$targetDb$suffix'),
          FileSystemEntityType.notFound,
          reason: suffix,
        );
      }
    }

    void expectAsBefore(File kept) {
      expect(File(targetDb).readAsBytesSync(), before);
      for (final entry in sidecars.entries) {
        expect(File('$targetDb${entry.key}').readAsBytesSync(), entry.value);
      }
      expect(kept.readAsBytesSync(), [7, 7]);
      expect(File(p.join(receipts, 'b.jpg')).existsSync(), isFalse);
      expectNoLeftovers();
    }

    // After the close the connection cannot be reopened: the journal is left and
    // the next start puts everything back.
    const afterClose = {
      RestoreStage.setAside,
      RestoreStage.swap,
      RestoreStage.commit,
    };

    for (final stage in RestoreStage.values) {
      final late = afterClose.contains(stage);

      test(
        '${stage.name}: ${late ? 'the journal stays and the start puts it back' : 'database, sidecars and photos as before'}',
        () async {
          for (final entry in sidecars.entries) {
            File('$targetDb${entry.key}').writeAsBytesSync(entry.value);
          }
          final kept = File(p.join(receipts, 'a.jpg'))
            ..writeAsBytesSync([7, 7]);
          final backup = await v2Backup();

          if (late) {
            await expectLater(
              failingAt(stage).restorePlain(backup),
              throwsA(
                isA<RestoreNeedsRestartException>().having(
                  (e) => '${e.cause}',
                  'cause',
                  contains('failure at ${stage.name}'),
                ),
              ),
            );
            expect(closed, 1);
            expect(RestoreJournal(targetDb).isOpen, isTrue);

            expect(await RestoreJournal.recoverInterrupted(targetDb), isTrue);
          } else {
            await expectLater(
              failingAt(stage).restorePlain(backup),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  'failure at ${stage.name}',
                ),
              ),
            );
            expect(closed, 0);
            expect(RestoreJournal(targetDb).isOpen, isFalse);
            expect(preCopyFiles(targetDb, kPreRestoreCopyKind), isEmpty);
          }

          expectAsBefore(kept);
        },
      );
    }

    for (final stage in afterClose) {
      test(
        '${stage.name}: the app opens the old data after the start',
        () async {
          await expectLater(
            failingAt(stage).restorePlain(await v2Backup()),
            throwsA(isA<RestoreNeedsRestartException>()),
          );

          await RestoreJournal.recoverInterrupted(targetDb);

          expect(attachmentPaths(targetDb), ['/keep.jpg']);
          expect(File('$targetDb-wal').existsSync(), isFalse);
        },
      );
    }
  });
  test('the two latest copies of the replaced database are kept', () async {
    var minute = 0;
    final restoring = BackupRestorer(
      databasePath: () async => targetDb,
      documentsDir: () async => targetDocs,
      schemaVersion: () => appSchema,
      closeDatabase: () async {},
      now: () => DateTime(2026, 11, 4, 9, minute++),
    );
    makeDb(targetDb, attachments: ['/gen0']);

    for (var generation = 1; generation <= 3; generation++) {
      final next = makeDb(
        p.join(root.path, 'gen$generation.db'),
        attachments: ['/gen$generation'],
      );
      await restoring.restorePlain(
        await buildBackupPackage(
          database: next,
          documentsDir: sourceDocs,
          schemaVersion: appSchema,
          date: DateTime(2026, 11, 4),
        ),
      );
    }

    final kept = preCopyFiles(targetDb, kPreRestoreCopyKind);
    expect(kept, hasLength(2));
    expect(
      [for (final copy in kept) attachmentPaths(copy.path).single],
      ['/gen1', '/gen2'],
    );
    expect(attachmentPaths(targetDb), ['/gen3']);
  });

  test('a restore keeps what is still in the WAL of the old database', () async {
    final live = sqlite3.open(targetDb);
    live.execute('PRAGMA journal_mode = WAL');
    live.execute(
      'CREATE TABLE appData (appDataKey TEXT PRIMARY KEY, appDataValue TEXT)',
    );
    live.execute("INSERT INTO appData VALUES ('dbVersion', '$appSchema')");
    live.execute('CREATE TABLE accounts (id TEXT)');
    live.execute('CREATE TABLE transactions (id TEXT)');
    live.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    live.execute("INSERT INTO accounts VALUES ('only-in-the-wal')");
    addTearDown(() {
      try {
        live.close();
      } catch (_) {}
    });

    // The app's connection is closed by the restorer; here the test closes it.
    final closing = BackupRestorer(
      databasePath: () async => targetDb,
      documentsDir: () async => targetDocs,
      schemaVersion: () => appSchema,
      closeDatabase: () async => live.close(),
    );
    await closing.restorePlain(await v2Backup());

    final kept = preCopyFiles(targetDb, kPreRestoreCopyKind).single;
    final db = sqlite3.open(kept.path, mode: OpenMode.readOnly);
    final ids = db.select('SELECT id FROM accounts').map((r) => r['id']);
    db.close();
    expect(ids, ['only-in-the-wal']);
  });
  test('package round trip keeps manifest data and photos', () async {
    final parsed = parseBackupPackage(await v2Backup());

    expect(parsed.schemaVersion, appSchema);
    expect(parsed.sourceDocumentsDir, sourceDocs);
    expect(parsed.photos.keys.toSet(), {'a.jpg', 'b.jpg'});
  });
}
