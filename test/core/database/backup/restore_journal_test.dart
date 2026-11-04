import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/restore_journal.dart';
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

      expect(await RestoreJournal.recoverInterrupted(dbPath), isTrue);

      expectOriginal();
    });

    test('with only the marker written', () async {
      await RestoreJournal(dbPath).begin(hadDatabase: true, photos: [photo]);

      expect(await RestoreJournal.recoverInterrupted(dbPath), isTrue);

      expectOriginal();
    });

    test('after only some files were set aside', () async {
      final journal = RestoreJournal(dbPath);
      await journal.begin(hadDatabase: true, photos: [photo]);
      File('$dbPath-wal').renameSync('$dbPath-wal$kRestoreAsideSuffix');
      File('$dbPath-shm').renameSync('$dbPath-shm$kRestoreAsideSuffix');

      expect(await RestoreJournal.recoverInterrupted(dbPath), isTrue);

      expectOriginal();
    });

    test('and goes on if going back was itself interrupted', () async {
      await swapped();
      // Going back had already put the sidecars and the database in place...
      File('$dbPath-wal$kRestoreAsideSuffix').renameSync('$dbPath-wal');
      // ...but the journal was still open when the app died again.
      expect(RestoreJournal(dbPath).isOpen, isTrue);

      expect(await RestoreJournal.recoverInterrupted(dbPath), isTrue);

      expectOriginal();
    });

    test('a second start has nothing left to do', () async {
      await swapped();
      await RestoreJournal.recoverInterrupted(dbPath);

      expect(await RestoreJournal.recoverInterrupted(dbPath), isFalse);

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

      expect(await RestoreJournal.recoverInterrupted(dbPath), isTrue);

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
    expect(await RestoreJournal.recoverInterrupted(dbPath), isFalse);

    expect(File(dbPath).readAsBytesSync(), original);
    expect(File('$dbPath-wal').readAsBytesSync(), [1, 2, 3]);
  });

  test(
    'the temporary files of a restore that died while preparing go',
    () async {
      File('$dbPath$kRestoreTempSuffix').writeAsBytesSync([1]);
      File('$dbPath.snapshot_tmp').writeAsBytesSync([1]);
      File(p.join('$dbPath$kRestorePhotosSuffix', 'x.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);

      expect(await RestoreJournal.recoverInterrupted(dbPath), isFalse);

      expect(File('$dbPath$kRestoreTempSuffix').existsSync(), isFalse);
      expect(File('$dbPath.snapshot_tmp').existsSync(), isFalse);
      expect(Directory('$dbPath$kRestorePhotosSuffix').existsSync(), isFalse);
      expect(File(dbPath).readAsBytesSync(), original);
    },
  );
}
