import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/database_snapshot.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:monekin/core/database/backup/restore_journal.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const _sidecars = {
  '-wal': [1, 2, 3],
  '-shm': [4, 5],
  '-journal': [6],
};

void main() {
  late Directory root;
  late String dbPath;
  late String photo;
  late List<int> original;

  setUp(() {
    root = Directory.systemTemp.createTempSync('restore_journal_test');
    dbPath = p.join(root.path, 'monekin.db');
    photo = p.join(root.path, 'receipts', 'b.jpg');
    final db = sqlite3.open(dbPath);
    db.execute('CREATE TABLE t (v TEXT)');
    db.execute("INSERT INTO t VALUES ('original')");
    db.close();
    original = File(dbPath).readAsBytesSync();
    for (final entry in _sidecars.entries) {
      File('$dbPath${entry.key}').writeAsBytesSync(entry.value);
    }
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// What a restore does up to the swap, without committing: the same steps as
  /// `BackupRestorer`, which a test cannot interrupt by killing the process.
  Future<RestoreJournal> swapped({bool hadDatabase = true}) async {
    final journal = RestoreJournal(dbPath);
    await journal.begin(hadDatabase: hadDatabase, photos: [photo]);
    File(photo)
      ..createSync(recursive: true)
      ..writeAsBytesSync([9]);
    await journal.moveLiveAside();
    File(dbPath).writeAsBytesSync([42, 42]);
    return journal;
  }

  void expectOriginal() {
    expect(File(dbPath).readAsBytesSync(), original);
    for (final entry in _sidecars.entries) {
      expect(File('$dbPath${entry.key}').readAsBytesSync(), entry.value);
    }
    expect(File(photo).existsSync(), isFalse);
    for (final suffix in const [
      kRestoreMarkerSuffix,
      kRestoreAsideSuffix,
      '-wal$kRestoreAsideSuffix',
    ]) {
      expect(File('$dbPath$suffix').existsSync(), isFalse, reason: suffix);
    }
    // The sidecars of these tests are placeholders, so read a copy of the file.
    final copy = File(p.join(root.path, 'check.db'))
      ..writeAsBytesSync(File(dbPath).readAsBytesSync());
    final reopened = sqlite3.open(copy.path, mode: OpenMode.readOnly);
    expect(reopened.select('SELECT v FROM t').single['v'], 'original');
    reopened.close();
  }

  group('the next start undoes a restore the app did not finish', () {
    test('after the database was swapped in', () async {
      await swapped();

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.undone,
      );

      expectOriginal();
    });

    test('with only the marker written', () async {
      await RestoreJournal(dbPath).begin(hadDatabase: true, photos: [photo]);

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.undone,
      );

      expectOriginal();
    });

    test('after only some files were set aside', () async {
      final journal = RestoreJournal(dbPath);
      await journal.begin(hadDatabase: true, photos: [photo]);
      File('$dbPath-wal').renameSync('$dbPath-wal$kRestoreAsideSuffix');
      File('$dbPath-shm').renameSync('$dbPath-shm$kRestoreAsideSuffix');

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.undone,
      );

      expectOriginal();
    });

    test('and goes on if going back was itself interrupted', () async {
      await swapped();
      // Going back had already put the sidecars and the database in place...
      File('$dbPath-wal$kRestoreAsideSuffix').renameSync('$dbPath-wal');
      // ...but the journal was still open when the app died again.
      expect(RestoreJournal(dbPath).isOpen, isTrue);

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.undone,
      );

      expectOriginal();
    });

    test('a second start has nothing left to do', () async {
      await swapped();
      await RestoreJournal.recoverInterrupted(dbPath);

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.nothing,
      );

      expectOriginal();
    });

    test('an unreadable marker still puts back what was set aside', () async {
      await swapped();
      File('$dbPath$kRestoreMarkerSuffix').writeAsStringSync('{not json');

      await RestoreJournal.recoverInterrupted(dbPath);

      expect(File(dbPath).readAsBytesSync(), original);
      expect(File('$dbPath-wal').readAsBytesSync(), [1, 2, 3]);
      expect(RestoreJournal(dbPath).isOpen, isFalse);
    });

    test('a first restore, with no database before, leaves none', () async {
      File(dbPath).deleteSync();
      for (final entry in _sidecars.entries) {
        File('$dbPath${entry.key}').deleteSync();
      }
      await swapped(hadDatabase: false);

      await RestoreJournal.recoverInterrupted(dbPath);

      expect(File(dbPath).existsSync(), isFalse);
      expect(File(photo).existsSync(), isFalse);
      expect(RestoreJournal(dbPath).isOpen, isFalse);
    });

    test('photos that were already there are never deleted', () async {
      final journal = RestoreJournal(dbPath);
      final kept = File(p.join(root.path, 'receipts', 'a.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([7]);
      await journal.begin(hadDatabase: true, photos: [photo]);

      await RestoreJournal.recoverInterrupted(dbPath);

      expect(kept.readAsBytesSync(), [7]);
    });
  });

  group('a restore that did finish', () {
    test('keeps the new database and only tidies up', () async {
      final journal = await swapped();
      await journal.commit();

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.undone,
      );

      expect(File(dbPath).readAsBytesSync(), [42, 42]);
      expect(File(photo).readAsBytesSync(), [9]);
      expect(File('$dbPath$kRestoreAsideSuffix').existsSync(), isFalse);
      expect(File('$dbPath-wal$kRestoreAsideSuffix').existsSync(), isFalse);
      expect(RestoreJournal(dbPath).isOpen, isFalse);
    });

    test('finish deletes the files set aside and the marker', () async {
      final journal = await swapped();
      await journal.commit();

      await journal.finish();

      expect(File('$dbPath$kRestoreAsideSuffix').existsSync(), isFalse);
      expect(journal.isOpen, isFalse);
      expect(File(dbPath).readAsBytesSync(), [42, 42]);
    });
  });

  test('without a marker nothing is touched', () async {
    expect(
      await RestoreJournal.recoverInterrupted(dbPath),
      RestoreRecovery.nothing,
    );

    expect(File(dbPath).readAsBytesSync(), original);
    expect(File('$dbPath-wal').readAsBytesSync(), [1, 2, 3]);
  });

  group('temporary files', () {
    final stale = DateTime.now().subtract(const Duration(minutes: 11));
    DateTime later() => DateTime.now().add(const Duration(minutes: 11));

    File make(String suffix, {DateTime? modified}) {
      final file = File('$dbPath$suffix')..writeAsBytesSync([1]);
      if (modified != null) file.setLastModifiedSync(modified);
      return file;
    }

    test('orphans of a restore that died while preparing go', () async {
      final tmp = make('$kRestoreTempSuffix.ab12', modified: stale);
      final snapshot = make('$kSnapshotSuffix.cd34', modified: stale);
      final legacy = make(kRestoreTempSuffix, modified: stale);
      final staged = File(p.join('$dbPath$kRestorePhotosSuffix.ef56', 'x.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);

      expect(
        await RestoreJournal.recoverInterrupted(dbPath, now: later),
        RestoreRecovery.nothing,
      );

      expect(tmp.existsSync(), isFalse);
      expect(snapshot.existsSync(), isFalse);
      expect(legacy.existsSync(), isFalse);
      expect(staged.parent.existsSync(), isFalse);
      expect(File(dbPath).readAsBytesSync(), original);
    });

    test('those of a live operation, younger than 10 minutes, stay', () async {
      final tmp = make('$kRestoreTempSuffix.ab12');
      final snapshot = make(
        '$kSnapshotSuffix.cd34',
        modified: DateTime.now().subtract(const Duration(minutes: 9)),
      );
      final staged = File(p.join('$dbPath$kRestorePhotosSuffix.ef56', 'x.jpg'))
        ..createSync(recursive: true);

      await RestoreJournal.recoverInterrupted(dbPath);

      expect(tmp.existsSync(), isTrue);
      expect(snapshot.existsSync(), isTrue);
      expect(staged.existsSync(), isTrue);
    });

    test('the clock decides, not the file system', () async {
      final tmp = make('$kRestoreTempSuffix.ab12');

      await RestoreJournal.recoverInterrupted(
        dbPath,
        now: () => DateTime.now().add(const Duration(minutes: 11)),
      );

      expect(tmp.existsSync(), isFalse);
    });

    test('with the lock taken nothing is deleted', () async {
      final tmp = make('$kRestoreTempSuffix.ab12', modified: stale);
      final lock = await RestoreLock.acquire(dbPath);

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.inProgress,
      );
      expect(tmp.existsSync(), isTrue);

      await lock.release();
    });

    test('two operations get two different names', () {
      expect(
        uniqueTempPath(dbPath, kRestoreTempSuffix),
        isNot(uniqueTempPath(dbPath, kRestoreTempSuffix)),
      );
      expect(
        uniqueTempPath(dbPath, kSnapshotSuffix),
        startsWith('$dbPath$kSnapshotSuffix.'),
      );
    });
  });

  group('a start without a database', () {
    test('puts back the one a restore set aside', () async {
      await swapped();
      // The state the race left: the marker and the new file gone, the old one aside.
      File('$dbPath$kRestoreMarkerSuffix').deleteSync();
      File(dbPath).deleteSync();
      File(
        photo,
      ).deleteSync(); // brought by the restore; not what is checked here

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.restoredMissing,
      );

      expectOriginal();
    });

    test('puts back the latest healthy copy kept before a restore', () async {
      final healthy = File(
        newPreCopyPath(dbPath, kPreRestoreCopyKind, DateTime(2026, 11, 4)),
      );
      sqlite3.open(healthy.path)
        ..execute('CREATE TABLE accounts (id TEXT)')
        ..close();
      final kept = healthy.readAsBytesSync();
      healthy.setLastModifiedSync(DateTime(2026, 11, 4));
      final newer = File(
        newPreCopyPath(dbPath, kPreRestoreCopyKind, DateTime(2026, 11, 5)),
      )..writeAsBytesSync([0, 0, 0]);
      newer.setLastModifiedSync(DateTime(2026, 11, 5));
      for (final part in const ['', '-wal', '-shm', '-journal']) {
        File('$dbPath$part').deleteSync();
      }
      File('$dbPath-wal').writeAsBytesSync([9]);

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.restoredMissing,
      );

      expect(File(dbPath).readAsBytesSync(), kept);
      expect(File('$dbPath-wal').existsSync(), isFalse);
      expect(healthy.existsSync(), isTrue, reason: 'the copy is kept');
    });

    test('with nothing to put back leaves none', () async {
      File(dbPath).deleteSync();

      expect(
        await RestoreJournal.recoverInterrupted(dbPath),
        RestoreRecovery.nothing,
      );
      expect(File(dbPath).existsSync(), isFalse);
    });

    test('never replaces a database that is there', () async {
      File('$dbPath$kRestoreAsideSuffix').writeAsBytesSync([5]);

      await RestoreJournal.recoverInterrupted(dbPath);

      expect(File(dbPath).readAsBytesSync(), original);
      expect(File('$dbPath$kRestoreAsideSuffix').existsSync(), isTrue);
    });
  });
}
