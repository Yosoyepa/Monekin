import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String dbPath;
  late int prepared;
  late List<String> ran;

  setUp(() {
    root = Directory.systemTemp.createTempSync('background_tasks_test');
    dbPath = p.join(root.path, 'monekin.db');
    prepared = 0;
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
}
