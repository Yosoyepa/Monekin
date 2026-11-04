// Flow 7 of the Finanzas IA emulator E2E (T002): the CSV export of the transactions.
// The export page is driven through the UI up to the native folder picker (which integration_test cannot
// handle); the file itself is written with the same service the page calls. The host script then copies it
// off the device (`run-as ... cat`) and runs tools/plantilla/verificar.py on it.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/app/settings/pages/backup/export_page.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/backup_database_service.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/core/utils/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'support/e2e_support.dart';

Future<List<Map<String, Object?>>> query(String sql) async {
  final rows = await AppDB.instance.customSelect(sql).get();
  return [for (final r in rows) r.data];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flow 7: CSV export of the transactions', (tester) async {
    await bootApp(tester);
    final account = await ensureAccount(
      'Efectivo',
      iniValue: 500000,
      date: DateTime(2026, 1, 1),
    );

    // Data with the awkward cases of the CSV: comma, quotes and a line break in text fields.
    final category =
        (await query(
              "SELECT id FROM categories WHERE parentCategoryID IS NULL AND type IN ('E','B') ORDER BY name LIMIT 1",
            )).first['id']
            as String;
    final income =
        (await query(
              "SELECT id FROM categories WHERE parentCategoryID IS NULL AND type IN ('I','B') ORDER BY name LIMIT 1",
            )).first['id']
            as String;
    final seeded = await query(
      "SELECT COUNT(*) AS n FROM transactions WHERE title LIKE 'E2E-CSV %'",
    );
    if ((seeded.first['n'] as int) == 0) {
      Future<void> add(
        String title,
        double value,
        DateTime date,
        String categoryId, {
        String? notes,
        required TransactionType type,
      }) => TransactionService.instance.insertTransaction(
        TransactionInDB(
          id: generateUUID(),
          date: date,
          accountID: account,
          value: value,
          title: title,
          notes: notes,
          type: type,
          categoryID: categoryId,
          isHidden: false,
        ),
      );
      await add(
        'E2E-CSV Sueldo',
        3200000,
        DateTime(2026, 10, 1, 8),
        income,
        type: TransactionType.income,
      );
      await add(
        'E2E-CSV Mercado, "grande"',
        -185430.5,
        DateTime(2026, 10, 7, 18, 30),
        category,
        notes: 'Lista del hogar\ncon salto de línea',
        type: TransactionType.expense,
      );
      await add(
        'E2E-CSV Café',
        -12300,
        DateTime(2026, 10, 9, 9, 5),
        category,
        type: TransactionType.expense,
      );
    }

    unawaited(RouteUtils.pushRoute(const ExportDataPage()));
    expect(
      await pumpUntilFound(tester, find.text('Respaldo de transacciones')),
      isTrue,
    );
    await tester.tap(find.text('Respaldo de transacciones'));
    await pumpFor(tester, const Duration(seconds: 2));
    await shot(tester, '07_export_page_csv');
    expect(find.text('Todas las transacciones'), findsOneWidget);

    final transactions = await TransactionService.instance
        .getTransactions(filters: const TransactionFilterSet())
        .first;
    final dir = await getTemporaryDirectory();
    final file = await BackupDatabaseService().exportSpreadsheet(
      dir.path,
      transactions,
    );
    final text = await file.readAsString();
    final lines = const LineSplitterLite().rowsOf(text);
    marker(
      'csv rows (without header): ${lines - 1} transactions: ${transactions.length}',
    );
    marker('csv header: ${text.split('\r\n').first}');
    expect(text.split('\r\n').first, startsWith('ID,Amount,Date,Title,Note'));
    marker('pull-export ${p.basename(file.path)}');
    await pumpFor(tester, const Duration(seconds: 4));
    marker('verify-export ${p.basename(file.path)}');
    await pumpFor(tester, const Duration(seconds: 25));
    expect(await File(file.path).exists(), isTrue);
  });
}

/// Counts CSV records (a quoted field may contain line breaks).
class LineSplitterLite {
  const LineSplitterLite();

  int rowsOf(String csv) {
    var inQuotes = false;
    var rows = 1;
    for (var i = 0; i < csv.length; i++) {
      final c = csv[i];
      if (c == '"') inQuotes = !inQuotes;
      if (!inQuotes && c == '\r' && i + 1 < csv.length && csv[i + 1] == '\n') {
        rows++;
        i++;
      }
    }
    return rows;
  }
}
