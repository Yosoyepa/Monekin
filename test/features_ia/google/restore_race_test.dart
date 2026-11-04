// A database open that runs while a restore is alive (T002, round 5): the recovery
// that every open runs, here in another isolate as the WorkManager one is, must leave
// the restore alone at every stage, and whatever happens the app ends with a database.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/database_snapshot.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:monekin/core/database/backup/restore_journal.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_restorer.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'backup_restorer_test.dart' show appSchema, attachmentPaths, makeDb;

/// What a background open does first, in an isolate of its own.
Future<String> recoverElsewhere(String dbPath) => Isolate.run(
  () async => (await RestoreJournal.recoverInterrupted(dbPath)).name,
);

List<String> leftovers(String dbPath) => [
  for (final e in Directory(p.dirname(dbPath)).listSync())
    if ([
      kRestoreTempSuffix,
      kRestorePhotosSuffix,
      kSnapshotSuffix,
      kRestoreAsideSuffix,
      kRestoreMarkerSuffix,
    ].any((s) => p.basename(e.path).contains(s)))
      p.basename(e.path),
];

void main() {
  late Directory root;
  late String sourceDocs;
  late String targetDocs;
  late String targetDb;
  late String receipts;
  late Uint8List before;
  late Uint8List backup;
  late int closed;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('restore_race_test');
    sourceDocs = p.join(root.path, 'source');
    targetDocs = p.join(root.path, 'target');
    receipts = p.join(targetDocs, 'finanzas_ia', 'receipts');
    final sourceReceipts = p.join(sourceDocs, 'finanzas_ia', 'receipts');
    Directory(sourceReceipts).createSync(recursive: true);
    Directory(receipts).createSync(recursive: true);
    targetDb = p.join(targetDocs, 'monekin.db');
    closed = 0;

    final photo = p.join(sourceReceipts, 'a.jpg');
    File(photo).writeAsBytesSync([1, 1, 1]);
    backup = await buildBackupPackage(
      database: makeDb(
        p.join(root.path, 'source.db'),
        attachments: [photo],
        inboxPaths: [photo],
      ),
      documentsDir: sourceDocs,
      schemaVersion: appSchema,
      date: DateTime(2026, 11, 4),
    );
    before = makeDb(targetDb, attachments: ['/keep.jpg']);
  });

  tearDown(() => root.deleteSync(recursive: true));

  BackupRestorer restorer({
    FutureOr<void> Function(RestoreStage stage)? onStage,
    Future<void> Function()? closeDatabase,
    PreCopiesState? preCopies,
    Future<void> Function(String source, String target)? snapshot,
  }) => BackupRestorer(
    databasePath: () async => targetDb,
    documentsDir: () async => targetDocs,
    schemaVersion: () => appSchema,
    closeDatabase: closeDatabase ?? () async => closed++,
    preCopies: preCopies,
    now: () => DateTime(2026, 11, 4),
    onStage: onStage,
    snapshot: snapshot,
  );

  /// The database is there, healthy, and is either the restored one or the old one.
  void expectAValidDatabase({required bool restored}) {
    expect(
      File(targetDb).existsSync(),
      isTrue,
      reason: 'the app has a database',
    );
    final db = sqlite3.open(targetDb, mode: OpenMode.readOnly);
    expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
    db.close();
    expect(
      attachmentPaths(targetDb),
      restored ? [p.join(receipts, 'a.jpg')] : ['/keep.jpg'],
    );
  }

  test(
    'a background open from the close callback leaves the restore alone',
    () async {
      final seen = <String>[];
      late bool markerOpen;
      late List<String> files;

      await restorer(
        closeDatabase: () async {
          closed++;
          seen
            ..add(await recoverElsewhere(targetDb))
            ..add((await RestoreJournal.recoverInterrupted(targetDb)).name);
          markerOpen = RestoreJournal(targetDb).isOpen;
          files = leftovers(targetDb);
        },
      ).restore(backup, unencryptedConfirmed: true);

      expect(seen, ['inProgress', 'inProgress']);
      expect(markerOpen, isTrue, reason: 'the marker is still there');
      expect(
        files.where((f) => f.contains(kRestoreTempSuffix)),
        hasLength(1),
        reason: 'and so is the temporary database',
      );
      expectAValidDatabase(restored: true);
      expect(leftovers(targetDb), isEmpty);
      expect(await recoverElsewhere(targetDb), 'nothing');
    },
  );

  group('a background open at the start of each stage', () {
    // What exists at the start of each stage, and so must survive the open.
    const withTemp = {
      RestoreStage.validate,
      RestoreStage.stagePhotos,
      RestoreStage.keepCurrent,
      RestoreStage.journal,
      RestoreStage.bringPhotos,
      RestoreStage.close,
      RestoreStage.setAside,
      RestoreStage.swap,
    };
    const withMarker = {
      RestoreStage.bringPhotos,
      RestoreStage.close,
      RestoreStage.setAside,
      RestoreStage.swap,
      RestoreStage.commit,
    };

    for (final stage in RestoreStage.values) {
      test(
        '${stage.name}: the restore finishes and the new database is there',
        () async {
          final seen = <String>[];
          late bool markerOpen;
          late List<String> files;

          await restorer(
            onStage: (s) async {
              if (s != stage) return;
              seen
                ..add(await recoverElsewhere(targetDb))
                ..add((await RestoreJournal.recoverInterrupted(targetDb)).name);
              markerOpen = RestoreJournal(targetDb).isOpen;
              files = leftovers(targetDb);
            },
          ).restore(backup, unencryptedConfirmed: true);

          expect(seen, ['inProgress', 'inProgress']);
          expect(markerOpen, withMarker.contains(stage), reason: 'marker');
          expect(
            files.any((f) => f.contains(kRestoreTempSuffix)),
            withTemp.contains(stage),
            reason: 'temporary database',
          );
          expect(closed, 1);
          expectAValidDatabase(restored: true);
          expect(leftovers(targetDb), isEmpty);
        },
      );

      test(
        '${stage.name}: if it fails there, the app is left with a database',
        () async {
          final seen = <String>[];
          Object? failure;

          try {
            await restorer(
              onStage: (s) async {
                if (s != stage) return;
                seen.add(await recoverElsewhere(targetDb));
                throw StateError('failure at ${s.name}');
              },
            ).restore(backup, unencryptedConfirmed: true);
          } catch (e) {
            failure = e;
          }

          expect(failure, isNotNull);
          expect(seen, ['inProgress']);
          // Before the close the restore already went back; after it, the next start does.
          final recovered = await RestoreJournal.recoverInterrupted(targetDb);
          expect(
            recovered,
            failure is RestoreNeedsRestartException
                ? RestoreRecovery.undone
                : RestoreRecovery.nothing,
          );
          expectAValidDatabase(restored: false);
          expect(File(targetDb).readAsBytesSync(), before);
          expect(File(p.join(receipts, 'a.jpg')).existsSync(), isFalse);
          expect(
            leftovers(targetDb).where((f) => !f.contains('pre_restore')),
            isEmpty,
          );
        },
      );
    }
  });

  test('a background open during the cleanup leaves it alone too', () async {
    final seen = <String>[];
    final stateFile = File(p.join(root.path, 'pre_copies.json'));

    await restorer(
      preCopies: PreCopiesState(() async {
        seen.add(await recoverElsewhere(targetDb));
        return stateFile;
      }),
    ).restore(backup, unencryptedConfirmed: true);

    expect(seen, ['inProgress']);
    expectAValidDatabase(restored: true);
  });

  test('the race the review reproduced ends with a database', () async {
    // The review's sequence: the old database is set aside, the swap fails, and the
    // recovery of a background open runs meanwhile.
    late String during;
    await expectLater(
      restorer(
        onStage: (s) async {
          if (s != RestoreStage.swap) return;
          during = await recoverElsewhere(targetDb);
          throw const FileSystemException('locked');
        },
      ).restore(backup, unencryptedConfirmed: true),
      throwsA(isA<RestoreNeedsRestartException>()),
    );
    expect(during, 'inProgress');
    expect(RestoreJournal(targetDb).isOpen, isTrue);
    expect(File(targetDb).existsSync(), isFalse);

    // Even with the marker lost, as the old recovery left it, the next start puts the
    // database that was set aside back.
    File('$targetDb$kRestoreMarkerSuffix').deleteSync();

    expect(
      await RestoreJournal.recoverInterrupted(targetDb),
      RestoreRecovery.restoredMissing,
    );
    expectAValidDatabase(restored: false);
  });
  group('the copy of the current database that a restore keeps', () {
    test('is made by a second snapshot if the first one fails', () async {
      var calls = 0;

      await restorer(
        snapshot: (source, target) {
          calls++;
          if (calls == 1) throw const FileSystemException('busy');
          return snapshotDatabase(source, target);
        },
      ).restore(backup, unencryptedConfirmed: true);

      expect(calls, 2);
      final copy = preCopyFiles(targetDb, kPreRestoreCopyKind).single;
      expect(attachmentPaths(copy.path), ['/keep.jpg']);
      final kept = sqlite3.open(copy.path, mode: OpenMode.readOnly);
      expect(kept.select('PRAGMA integrity_check').single.values.single, 'ok');
      kept.close();
    });

    test('is the file as it is only after both snapshots fail', () async {
      var calls = 0;

      await restorer(
        snapshot: (source, target) async {
          calls++;
          File(target).writeAsBytesSync([0]); // a half-written snapshot
          throw const FileSystemException('busy');
        },
      ).restore(backup, unencryptedConfirmed: true);

      expect(calls, 2);
      final copy = preCopyFiles(targetDb, kPreRestoreCopyKind).single;
      expect(copy.readAsBytesSync(), before);
    });
  });
}
