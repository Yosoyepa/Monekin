// Flow 13 of the Finanzas IA emulator E2E (T002, round 2): the local backup sealed with a password (v3).
// The password sheet, the wrong-password error and the right-password restore run through the real UI sheets and
// the same functions the settings pages call. The native folder picker and the share sheet cannot be driven from
// integration_test: the host script (docs/e2e/run_e2e.ps1) closes the folder picker with the back key.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/app/settings/pages/backup/export_page.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/backup_database_service.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/core/utils/unique_app_widgets_keys.dart';
import 'package:monekin/core/utils/uuid.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_key_store.dart';
import 'package:monekin/features_ia/google/backup_password_sheets.dart';
import 'package:monekin/features_ia/google/restore_flow.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'support/e2e_support.dart';

const goodPassword = 'E2e-Clave-Buena-2026';
const wrongPassword = 'clave-equivocada-77';

Future<List<Map<String, Object?>>> query(String sql) async {
  final rows = await AppDB.instance.customSelect(sql).get();
  return [for (final r in rows) r.data];
}

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

  testWidgets('flow 13: password, sealed export, wrong password, right password', (
    tester,
  ) async {
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
    await addExpense(account, category, 'E2E-BAK Arriendo', 1200000);
    await addExpense(account, category, 'E2E-BAK Mercado', 150000);
    await addExpense(account, category, 'E2E-BAK Transporte', 32500);
    final sealedCount = await transactionCount();
    expect(sealedCount, 3);

    // 1. The first full export asks to create the password (a short one is weak, a mismatch blocks).
    final keyStore = SecureBackupKeyStore();
    await keyStore.clear();
    unawaited(RouteUtils.pushRoute(const ExportDataPage()));
    expect(await pumpUntilFound(tester, find.text('Descargar')), isTrue);
    await shot(tester, 'R2_13_export_page');
    // «Descargar» asks for the password first and then opens the native folder picker, which stops the
    // test engine from drawing frames: the page is captured and the same password step is called directly.
    Navigator.of(tester.element(find.byType(ExportDataPage))).pop();
    await pumpFor(tester, const Duration(seconds: 1));
    unawaited(ensureBackupKey(navigatorKey.currentContext!));
    expect(
      await pumpUntilFound(tester, find.text('Crear contraseña de copias')),
      isTrue,
      reason: 'the password sheet did not open on the first full export',
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'corta');
    await tester.enterText(fields.last, 'otra');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(find.text('Débil'), findsOneWidget);
    final saveButton = find.widgetWithText(FilledButton, 'Guardar contraseña');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    await shot(tester, 'R2_13_password_weak_mismatch');
    await tester.enterText(fields.first, goodPassword);
    await tester.enterText(fields.last, goodPassword);
    await pumpFor(tester, const Duration(seconds: 1));
    await shot(tester, 'R2_13_password_strong');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.tap(saveButton);
    await pumpFor(tester, const Duration(seconds: 4));
    final key = await keyStore.load();
    expect(key, isNotNull, reason: 'the derived key was not stored');
    marker(
      'backup key stored: kdf memory=${key!.params.memoryKiB} KiB iterations=${key.params.iterations}',
    );

    // 2. The sealed file, made by the same function the page uses, is not readable without the password.
    final dir = await getTemporaryDirectory();
    final file = await BackupDatabaseService().exportEncryptedBackup(
      dir.path,
      key,
    );
    final bytes = await file.readAsBytes();
    final text = String.fromCharCodes(bytes);
    marker(
      'sealed export ${file.uri.pathSegments.last}: ${bytes.length} bytes',
    );
    expect(isEncryptedBackup(bytes), isTrue);
    expect(text.contains('SQLite format 3'), isFalse);
    expect(text.contains('E2E-BAK'), isFalse);
    expect(file.path.endsWith('.fia'), isTrue);

    // 3. The data changes after the export, and this phone forgets its key (a restore on another phone).
    await addExpense(account, category, 'E2E-BAK Despues de la copia', 9900);
    expect(await transactionCount(), sealedCount + 1);
    await keyStore.clear();
    final dbPath = await AppDB.instance.databasePath;

    // 4. Wrong password: the error shows, the sheet can be dismissed and nothing changes.
    final service = BackupDatabaseService();
    final first = runRestoreAttempts(
      navigatorKey.currentContext!,
      (password) => service.restorePackage(bytes, password: password),
    );
    expect(
      await pumpUntilFound(tester, find.text('Contraseña de la copia')),
      isTrue,
      reason: 'the restore did not ask for the password',
    );
    await shot(tester, 'R2_13_restore_password');
    await tester.enterText(find.byType(TextField).last, wrongPassword);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(FilledButton, 'Restaurar'));
    expect(
      await pumpUntilFound(
        tester,
        find.text('Esa contraseña no es correcta. Inténtalo de nuevo.'),
        timeout: const Duration(seconds: 60),
      ),
      isTrue,
      reason: 'no wrong-password error',
    );
    await shot(tester, 'R2_13_restore_wrong_password');
    await tester.tapAt(const Offset(20, 60));
    expect(await first.timeout(const Duration(seconds: 20)), isFalse);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(
      await transactionCount(),
      sealedCount + 1,
      reason: 'a wrong password changed the data',
    );
    marker(
      'wrong password: nothing changed, ${await transactionCount()} transactions',
    );

    // 5. Right password: restores the data of the export. The closed connection makes the pages under the
    // restart dialog fail while they rebuild (BUG-08): collect those errors and report them.
    final restoreErrors = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) =>
        restoreErrors.add(details.exceptionAsString().split('\n').first);
    addTearDown(() => FlutterError.onError = previousOnError);
    final second = runRestoreAttempts(
      navigatorKey.currentContext!,
      (password) => service.restorePackage(bytes, password: password),
    );
    expect(
      await pumpUntilFound(tester, find.text('Contraseña de la copia')),
      isTrue,
    );
    await tester.enterText(find.byType(TextField).last, goodPassword);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(FilledButton, 'Restaurar'));
    expect(await second.timeout(const Duration(seconds: 90)), isTrue);
    unawaited(showRestartRequiredPage(navigatorKey.currentContext!));
    await pumpFor(tester, const Duration(seconds: 2));
    await shot(tester, 'R2_13_restore_done');
    expect(find.text('Copia restaurada'), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 3));
    FlutterError.onError = previousOnError;
    while (tester.takeException() != null) {}
    marker(
      'BUG-08 errors under the restart dialog: ${restoreErrors.length} ${restoreErrors.toSet().toList()}',
    );

    // The running connection is closed: read the restored file directly.
    final restored = sqlite.sqlite3.open(
      dbPath,
      mode: sqlite.OpenMode.readOnly,
    );
    final titles = restored
        .select(
          "SELECT title FROM transactions WHERE title LIKE 'E2E-BAK %' ORDER BY title",
        )
        .map((r) => r['title'] as String)
        .toList();
    restored.close();
    marker('restored titles: $titles');
    expect(titles, [
      'E2E-BAK Arriendo',
      'E2E-BAK Mercado',
      'E2E-BAK Transporte',
    ]);
    expect(File(dbPath).existsSync(), isTrue);
  });
}
