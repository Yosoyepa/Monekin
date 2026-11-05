// E004 test 3: a restore killed halfway and the restore lock against WorkManager, on a real device.
// The host script (docs/e2e/run_restore_e2e.ps1) reads the markers this test prints:
//   E2E_MODE=kill-<stage>: the restore stops at <stage> and waits; the host runs `am force-stop`.
//   E2E_MODE=lock: the restore holds the lock at `validate`; the test queues a WorkManager task that starts at
//   once, and then another one when the lock is free. The log shows what each did.
//   E2E_MODE=bgflag: the test raises a flag of this process beside the database, as a background run does while
//   it works, and starts a restore. The restore waits for the flag, which the test removes after 10 s.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/backup_database_service.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/utils/uuid.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_restorer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'support/e2e_support.dart';

const mode = String.fromEnvironment('E2E_MODE');
const password = 'E2e-Clave-Buena-2026';

Future<List<Map<String, Object?>>> query(String sql) async {
  final rows = await AppDB.instance.customSelect(sql).get();
  return [for (final r in rows) r.data];
}

/// Top level so the closure sent to the isolate captures nothing but [path].
Future<bool> heldFromAnotherIsolate(String path) =>
    Isolate.run(() => RestoreLock.isHeld(path));

/// How many background-run flags are beside the database.
int backgroundFlagCount(String dbPath) => File(dbPath).parent
    .listSync()
    .where((e) => e.path.contains('$kRestoreLockName.bg.'))
    .length;

Future<int> transactionCount() async =>
    (await query('SELECT COUNT(*) AS n FROM transactions')).first['n'] as int;

Future<void> addExpense(
  String account,
  String category,
  String title,
  double value,
) => TransactionService.instance.insertTransaction(
  TransactionInDB(
    id: generateUUID(),
    date: DateTime.now().subtract(const Duration(hours: 2)),
    accountID: account,
    value: -value,
    title: title,
    type: TransactionType.expense,
    categoryID: category,
    isHidden: false,
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restore interrupted or locked: $mode', (tester) async {
    expect(mode, isNotEmpty, reason: 'pass --dart-define=E2E_MODE=...');
    await bootApp(tester);
    await resetData();
    final account = await ensureAccount(
      'Efectivo',
      iniValue: 500000,
      date: DateTime(2026, 1, 1),
    );
    final category =
        (await query(
              "SELECT id FROM categories WHERE parentCategoryID IS NULL AND type IN ('E','B') ORDER BY name LIMIT 1",
            )).first['id']
            as String;
    for (final n in [1, 2, 3]) {
      await addExpense(account, category, 'E2E-RST Base $n', 10000.0 * n);
    }

    // The sealed copy holds the 3 base transactions.
    final key = await createBackupKey(password);
    final dir = await getTemporaryDirectory();
    final file = await BackupDatabaseService().exportEncryptedBackup(
      dir.path,
      key,
    );
    final bytes = await file.readAsBytes();
    expect(isEncryptedBackup(bytes), isTrue);
    marker('sealed copy ${file.uri.pathSegments.last}: ${bytes.length} bytes');

    // The live database then holds 5: the restore would bring it back to 3.
    for (final n in [1, 2]) {
      await addExpense(account, category, 'E2E-RST Extra $n', 5000.0 * n);
    }
    marker('live transactions before the restore: ${await transactionCount()}');

    final db = AppDB.instance;
    final restorer = BackupRestorer(
      databasePath: () => db.databasePath,
      documentsDir: () async => (await getApplicationDocumentsDirectory()).path,
      schemaVersion: () => db.schemaVersion,
      closeDatabase: db.close,
      preCopies: PreCopiesState.inSupportDir(),
      onStage: (stage) async {
        marker('restore-stage ${stage.name}');
        if (mode == 'bgflag' && stage == RestoreStage.keepCurrent) {
          final flags = backgroundFlagCount(await db.databasePath);
          marker('background flags at keepCurrent: $flags');
        }
        if (mode == 'kill-${stage.name}') {
          marker('hold ${stage.name}');
          // The outer loop keeps pumping frames; this only waits in real time.
          await Future<void>.delayed(const Duration(seconds: 120));
        }
        if (mode.startsWith('lock') && stage == RestoreStage.validate) {
          marker('lock-held');
          if (mode == 'lock') {
            await Workmanager().registerOneOffTask(
              'e2e-bg-locked',
              kTaskNoticeScan,
            );
            marker('bg-scheduled e2e-bg-locked');
          }
          // The same check the background task makes, from another isolate of this process, while the lock is held.
          final path = await db.databasePath;
          marker(
            'isHeld from another isolate (lock held by the restore): ${await heldFromAnotherIsolate(path)}',
          );
          // The host finds the job, forces it and lists the database folder before and after.
          await Future<void>.delayed(const Duration(seconds: 45));
          marker('lock-hold-ended');
        }
      },
    );

    if (mode == 'bgflag') {
      // What a background run that works on the database leaves beside it.
      final dbPath = await db.databasePath;
      final flag = File(p.join(p.dirname(dbPath), '$kRestoreLockName.bg.e2e'))
        ..writeAsStringSync(processToken());
      marker('bg-flag raised ${p.basename(flag.path)}');
      unawaited(
        Future<void>.delayed(const Duration(seconds: 10)).then((_) {
          flag.deleteSync();
          marker('bg-flag removed');
        }),
      );
    }

    var done = false;
    Object? failure;
    unawaited(
      restorer
          .restore(bytes, resolveKey: resolverFromPassword(password))
          .then((_) => done = true, onError: (Object e) => failure = e),
    );
    final end = DateTime.now().add(const Duration(minutes: 4));
    while (!done && failure == null && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    marker('restore returned: done=$done failure=$failure');
    expect(done, isTrue, reason: 'the restore did not finish: $failure');

    if (mode == 'lock') {
      // The lock is free again: the same task now opens the database and runs.
      await Workmanager().registerOneOffTask('e2e-bg-free', kTaskNoticeScan);
      marker('bg-scheduled e2e-bg-free');
      await pumpFor(tester, const Duration(seconds: 30));
    }
    marker('test end');
  });
}
