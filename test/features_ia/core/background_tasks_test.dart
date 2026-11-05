import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/restore_journal.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
import 'package:path/path.dart' as p;

/// The background flags beside the database: a run that may hold it has one.
List<String> backgroundFlags(String dbPath) => [
  for (final e in Directory(p.dirname(dbPath)).listSync())
    if (p.basename(e.path).startsWith('$kRestoreLockName.bg.')) e.path,
];

void main() {
  late Directory root;
  late String dbPath;
  late int prepared;
  late int closed;
  late List<String> ran;

  setUp(() {
    root = Directory.systemTemp.createTempSync('background_tasks_test');
    dbPath = p.join(root.path, 'monekin.db');
    prepared = 0;
    closed = 0;
    ran = [];
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<bool> execute(String task) => executeBackgroundTask(
    task,
    databasePath: () async => dbPath,
    prepare: () async => prepared++,
    run: (name) async {
      ran.add(name);
      return true;
    },
    close: () async => closed++,
  );

  test(
    'with a restore holding the lock it opens the database 0 times',
    () async {
      final lock = (await RestoreLock.tryAcquire(dbPath))!;

      expect(await execute(kTaskBudgetCheck), isFalse);
      expect(await execute(kTaskDriveBackup), isFalse);

      expect(prepared, 0);
      expect(ran, isEmpty);
      await lock.release();
    },
  );

  test('with the restore marker on disk it opens nothing', () async {
    File('$dbPath$kRestoreMarkerSuffix').writeAsStringSync('{}');

    expect(await execute(kTaskNoticeScan), isFalse);

    expect(prepared, 0, reason: 'prepare is what opens AppDB');
    expect(ran, isEmpty);
  });

  test('with a set-aside database and no live one it opens nothing', () async {
    File('$dbPath$kRestoreAsideSuffix').writeAsBytesSync([1]);

    expect(await execute(kTaskNoticeScan), isFalse);

    expect(prepared, 0);
    expect(ran, isEmpty);
    expect(File(dbPath).existsSync(), isFalse, reason: 'no database is made');
  });

  test('a set-aside database beside a live one is not a restore', () async {
    File(dbPath).writeAsBytesSync([1]);
    File('$dbPath$kRestoreAsideSuffix').writeAsBytesSync([2]);

    expect(await execute(kTaskNoticeScan), isTrue);
    expect(prepared, 1);
  });

  test('without it the task runs', () async {
    expect(await execute(kTaskBudgetCheck), isTrue);

    expect(prepared, 1);
    expect(ran, [kTaskBudgetCheck]);
    expect(
      await RestoreLock.isHeld(dbPath),
      isFalse,
      reason: 'taken by no one',
    );
  });

  test('once the restore is over the next run goes ahead', () async {
    final lock = (await RestoreLock.tryAcquire(dbPath))!;
    expect(await execute(kTaskBudgetCheck), isFalse);

    await lock.release();

    expect(await execute(kTaskBudgetCheck), isTrue);
    expect(prepared, 1);
  });

  test(
    'a run that starts once the restore holds the lock lowers its flag',
    () async {
      final lock = (await RestoreLock.tryAcquire(dbPath))!;

      expect(await execute(kTaskBudgetCheck), isFalse);

      expect(prepared, 0, reason: 'nothing is prepared');
      expect(backgroundFlags(dbPath), isEmpty);
      await lock.release();
    },
  );

  test(
    'a run closes the database once and lowers its flag after the close, when it succeeds',
    () async {
      var flagsWhileRunning = 0;
      var flagsWhileClosing = 0;

      final ok = await executeBackgroundTask(
        kTaskBudgetCheck,
        databasePath: () async => dbPath,
        prepare: () async => prepared++,
        run: (_) async {
          flagsWhileRunning = backgroundFlags(dbPath).length;
          return true;
        },
        close: () async {
          closed++;
          flagsWhileClosing = backgroundFlags(dbPath).length;
        },
      );

      expect(ok, isTrue);
      expect(flagsWhileRunning, 1, reason: 'the flag stands while it runs');
      expect(flagsWhileClosing, 1, reason: 'and still at the close');
      expect(closed, 1);
      expect(backgroundFlags(dbPath), isEmpty);
    },
  );

  test(
    'a run that skips closes the database once and lowers its flag',
    () async {
      final lock = (await RestoreLock.tryAcquire(dbPath))!;

      expect(await execute(kTaskBudgetCheck), isFalse);

      expect(closed, 1);
      expect(backgroundFlags(dbPath), isEmpty);
      await lock.release();
    },
  );

  test(
    'a run whose task throws closes the database once and lowers its flag',
    () async {
      await expectLater(
        executeBackgroundTask(
          kTaskBudgetCheck,
          databasePath: () async => dbPath,
          prepare: () async => prepared++,
          run: (_) async => throw StateError('the task failed'),
          close: () async => closed++,
        ),
        throwsStateError,
      );

      expect(closed, 1);
      expect(backgroundFlags(dbPath), isEmpty);
    },
  );
}
