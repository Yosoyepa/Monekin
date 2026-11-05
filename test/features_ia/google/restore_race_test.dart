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
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
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

/// The background flags beside the database: a run that may hold it has one.
List<String> backgroundFlags(String dbPath) => [
  for (final e in Directory(p.dirname(dbPath)).listSync())
    if (p.basename(e.path).startsWith('$kRestoreLockName.bg.')) e.path,
];

/// What the accounts of the database at [dbPath] hold, in order.
List<String> accountIds(String dbPath) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    return [
      for (final r in db.select('SELECT id FROM accounts ORDER BY rowid'))
        r['id'] as String,
    ];
  } finally {
    db.close();
  }
}

/// A background run in an isolate of its own, as the WorkManager one is. It sends the
/// port that resumes it, reports that it is paused before it opens the database, and
/// then reports what the run returned.
Future<void> _runPausedBeforeOpen(List<Object> args) async {
  final dbPath = args[0] as String;
  final reports = args[1] as SendPort;
  final gate = ReceivePort();
  reports.send(gate.sendPort);
  Database? db;
  try {
    final ran = await executeBackgroundTask(
      kTaskBudgetCheck,
      databasePath: () async => dbPath,
      prepare: () async {
        reports.send('paused');
        await gate.first;
        gate.close();
        db = sqlite3.open(dbPath);
      },
      run: (_) async {
        db!.execute("INSERT INTO accounts VALUES ('written by the run')");
        return true;
      },
      close: () async => db?.close(),
    );
    reports.send(ran);
  } catch (e) {
    reports.send('failed: $e');
  }
}

/// A background run that opens the database and starts a write transaction before it
/// reports and waits to be resumed. It commits in the run, then closes.
Future<void> _runWithOpenTransaction(List<Object> args) async {
  final dbPath = args[0] as String;
  final reports = args[1] as SendPort;
  final gate = ReceivePort();
  reports.send(gate.sendPort);
  Database? db;
  try {
    final ran = await executeBackgroundTask(
      kTaskBudgetCheck,
      databasePath: () async => dbPath,
      prepare: () async {
        db = sqlite3.open(dbPath)
          ..execute('BEGIN IMMEDIATE')
          ..execute("INSERT INTO accounts VALUES ('written by the run')");
        reports.send('in transaction');
        await gate.first;
        gate.close();
      },
      run: (_) async {
        db!.execute('COMMIT');
        return true;
      },
      close: () async => db?.close(),
    );
    reports.send(ran);
  } catch (e) {
    reports.send('failed: $e');
  }
}

/// The token of a process that is not this one: the next pid.
String anotherProcess() => '${int.parse(processToken().split(':').first) + 1}';

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
    Duration backgroundWait = const Duration(seconds: 60),
  }) => BackupRestorer(
    databasePath: () async => targetDb,
    documentsDir: () async => targetDocs,
    schemaVersion: () => appSchema,
    closeDatabase: closeDatabase ?? () async => closed++,
    preCopies: preCopies,
    backgroundWait: backgroundWait,
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
  test(
    'a run paused before it opens the database holds the restore back until it is done',
    () async {
      final port = ReceivePort();
      final reports = StreamIterator<Object?>(port);
      await Isolate.spawn(_runPausedBeforeOpen, [targetDb, port.sendPort]);
      await reports.moveNext();
      final resume = reports.current as SendPort;
      await reports.moveNext();
      expect(reports.current, 'paused');

      final stages = <RestoreStage>[];
      var flagsAtKeepCurrent = -1;
      final restoring = restorer(
        backgroundWait: const Duration(seconds: 30),
        onStage: (s) {
          stages.add(s);
          if (s == RestoreStage.keepCurrent) {
            flagsAtKeepCurrent = backgroundFlags(targetDb).length;
          }
        },
      ).restore(backup, unencryptedConfirmed: true);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(stages, isNot(contains(RestoreStage.keepCurrent)));
      expect(backgroundFlags(targetDb), hasLength(1));

      resume.send(true);
      await reports.moveNext();
      expect(reports.current, true, reason: 'the run finished');
      await restoring;
      await reports.cancel();
      port.close();

      expect(flagsAtKeepCurrent, 0, reason: 'no flag stood at keepCurrent');
      expect(backgroundFlags(targetDb), isEmpty);
      expectAValidDatabase(restored: true);
      expect(File('$targetDb-journal').existsSync(), isFalse);
      expect(leftovers(targetDb), isEmpty);
      expect(
        accountIds(preCopyFiles(targetDb, kPreRestoreCopyKind).single.path),
        ['written by the run'],
        reason: 'the write reached the live database before it was kept',
      );
    },
  );

  test(
    'a run with its database open and a write in progress holds the restore back until it commits',
    () async {
      final port = ReceivePort();
      final reports = StreamIterator<Object?>(port);
      await Isolate.spawn(_runWithOpenTransaction, [targetDb, port.sendPort]);
      await reports.moveNext();
      final resume = reports.current as SendPort;
      await reports.moveNext();
      expect(reports.current, 'in transaction');

      final stages = <RestoreStage>[];
      final restoring = restorer(
        backgroundWait: const Duration(seconds: 30),
        onStage: stages.add,
      ).restore(backup, unencryptedConfirmed: true);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(stages, isNot(contains(RestoreStage.keepCurrent)));
      expect(backgroundFlags(targetDb), hasLength(1));

      resume.send(true);
      await reports.moveNext();
      expect(reports.current, true, reason: 'the run committed and finished');
      await restoring;
      await reports.cancel();
      port.close();

      expect(backgroundFlags(targetDb), isEmpty);
      expectAValidDatabase(restored: true);
      expect(File('$targetDb-journal').existsSync(), isFalse);
      expect(leftovers(targetDb), isEmpty);
      expect(
        accountIds(preCopyFiles(targetDb, kPreRestoreCopyKind).single.path),
        ['written by the run'],
        reason: 'the commit reached the live database before it was kept',
      );
    },
  );

  test(
    'a flag of a process that no longer lives counts for nothing, whatever its date: it is deleted and the restore goes on',
    () async {
      final dir = p.dirname(targetDb);
      final stale = File(p.join(dir, '$kRestoreLockName.bg.stale'))
        ..writeAsStringSync(anotherProcess())
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 2)),
        );
      final ahead = File(p.join(dir, '$kRestoreLockName.bg.ahead'))
        ..writeAsStringSync(anotherProcess())
        ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 2)));

      await restorer(
        backgroundWait: const Duration(seconds: 2),
      ).restore(backup, unencryptedConfirmed: true);

      expect(stale.existsSync(), isFalse);
      expect(ahead.existsSync(), isFalse);
      expectAValidDatabase(restored: true);
    },
  );

  test(
    'a fresh flag that never ends makes the restore give up and touch nothing',
    () async {
      final before = File(targetDb).readAsBytesSync();
      final stuck = File(
        p.join(p.dirname(targetDb), '$kRestoreLockName.bg.stuck'),
      );

      await expectLater(
        restorer(
          backgroundWait: const Duration(seconds: 1),
          onStage: (s) {
            // Raised once the restore has passed its first wait, so the temporary
            // files exist when the second one gives up.
            if (s == RestoreStage.validate) {
              stuck.writeAsStringSync(processToken());
            }
          },
        ).restore(backup, unencryptedConfirmed: true),
        throwsA(isA<RestoreBusyException>()),
      );

      expect(
        File(targetDb).readAsBytesSync(),
        before,
        reason: 'the database is untouched',
      );
      expect(RestoreJournal(targetDb).isOpen, isFalse, reason: 'no marker');
      expect(leftovers(targetDb), isEmpty, reason: 'no temporary file');
      expect(
        File(RestoreLock.heldPath(targetDb)).existsSync(),
        isFalse,
        reason: 'the lock was let go',
      );
      expect(stuck.existsSync(), isTrue, reason: 'the flag belongs to its run');
    },
  );

  test(
    'a recovery from another isolate leaves the holder file of a restore alone',
    () async {
      final held = File(RestoreLock.heldPath(targetDb))
        ..writeAsStringSync(processToken());

      expect(await recoverElsewhere(targetDb), 'nothing');

      expect(held.readAsStringSync(), processToken());
    },
  );

  test(
    'a run of this process holds the restore back however old its flag is',
    () async {
      final port = ReceivePort();
      final reports = StreamIterator<Object?>(port);
      await Isolate.spawn(_runPausedBeforeOpen, [targetDb, port.sendPort]);
      await reports.moveNext();
      final resume = reports.current as SendPort;
      await reports.moveNext();
      expect(reports.current, 'paused');

      // The paused run's flag, dated two minutes ago, and another flag of this process
      // dated two minutes ahead. Neither date decides anything.
      final aged = File(backgroundFlags(targetDb).single)
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 2)),
        );
      final ahead =
          File(p.join(p.dirname(targetDb), '$kRestoreLockName.bg.ahead'))
            ..writeAsStringSync(processToken())
            ..setLastModifiedSync(
              DateTime.now().add(const Duration(minutes: 2)),
            );

      final before = File(targetDb).readAsBytesSync();
      await expectLater(
        restorer(
          backgroundWait: const Duration(seconds: 1),
        ).restore(backup, unencryptedConfirmed: true),
        throwsA(isA<RestoreBusyException>()),
      );
      expect(
        File(targetDb).readAsBytesSync(),
        before,
        reason: 'the database is untouched',
      );
      expect(RestoreJournal(targetDb).isOpen, isFalse);
      expect(leftovers(targetDb), isEmpty);
      expect(aged.existsSync(), isTrue, reason: 'the live run keeps its flag');
      expect(ahead.existsSync(), isTrue, reason: 'and so does the other one');

      // The other task ends. The paused run still holds the restore back, until it
      // closes the database and lowers its flag.
      ahead.deleteSync();
      final stages = <RestoreStage>[];
      final restoring = restorer(
        backgroundWait: const Duration(seconds: 30),
        onStage: stages.add,
      ).restore(backup, unencryptedConfirmed: true);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(stages, isNot(contains(RestoreStage.keepCurrent)));
      expect(backgroundFlags(targetDb), hasLength(1));

      resume.send(true);
      await reports.moveNext();
      expect(reports.current, true, reason: 'the run finished');
      await restoring;
      await reports.cancel();
      port.close();

      expect(backgroundFlags(targetDb), isEmpty);
      expectAValidDatabase(restored: true);
      expect(
        accountIds(preCopyFiles(targetDb, kPreRestoreCopyKind).single.path),
        ['written by the run'],
      );
    },
  );

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
