// Flow 6 of the Finanzas IA emulator E2E (T002): insights with the real Gemini and one recategorization.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/core/utils/uuid.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/insights/insights_page.dart';

import 'support/e2e_support.dart';

Future<List<Map<String, Object?>>> query(String sql) async {
  final rows = await AppDB.instance.customSelect(sql).get();
  return [for (final r in rows) r.data];
}

Future<void> ensureAiConfigured() async {
  final service = AiService.instance as AiServiceImpl;
  if (await service.isConfigured()) return;
  await service.saveConfig(aiPresets[AiProviderId.gemini]!);
  await service.saveKey(geminiKey);
}

Future<void> seed(String account, Map<String, String> categories) async {
  final already = await query(
    "SELECT COUNT(*) AS n FROM transactions WHERE title LIKE 'E2E-INS %'",
  );
  if ((already.first['n'] as int) > 0) return;
  final now = DateTime.now();
  Future<void> add(
    String title,
    double value,
    DateTime date,
    String category,
  ) => TransactionService.instance.insertTransaction(
    TransactionInDB(
      id: generateUUID(),
      date: date,
      accountID: account,
      value: -value,
      title: 'E2E-INS $title',
      type: TransactionType.expense,
      categoryID: category,
      isHidden: false,
    ),
  );
  final first = categories.values.first;
  final second = categories.values.elementAt(1);
  final other = categories['Others'] ?? categories.values.last;
  // A subscription that repeats for several months, plus bigger one-off expenses this month.
  for (var back = 3; back >= 0; back--) {
    await add('Netflix', 32900, DateTime(now.year, now.month - back, 1), first);
  }
  await add('Mercado', 150000, DateTime(now.year, now.month, 2), second);
  await add('Restaurante', 85000, DateTime(now.year, now.month, 3), second);
  await add('Mercado', 90000, DateTime(now.year, now.month - 1, 10), second);
  await add(
    'Uber al aeropuerto',
    28500,
    DateTime(now.year, now.month, 3),
    other,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flow 6: insights figures, Gemini tips and one recategorization', (
    tester,
  ) async {
    await bootApp(tester);
    // BUG-05: a fl_chart PieChart under these pages repaints with badges that no longer match its sections
    // (RangeError). Collect those errors for the whole flow so the rest of it is still verified.
    final paintErrors = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) =>
        paintErrors.add(details.exceptionAsString().split('\n').first);
    addTearDown(() {
      FlutterError.onError = previousOnError;
    });
    await ensureAiConfigured();
    final account = await ensureAccount(
      'Efectivo',
      iniValue: 500000,
      date: DateTime(2026, 1, 1),
    );
    final rows = await query(
      "SELECT id, name FROM categories WHERE parentCategoryID IS NULL AND type IN ('E','B') ORDER BY name",
    );
    final byName = {
      for (final r in rows) r['name'] as String: r['id'] as String,
    };
    marker('categories: ${byName.keys.toList()}');
    expect(byName, isNotEmpty);
    final ordered = <String, String>{
      if (byName.containsKey('Housing')) 'Housing': byName['Housing']!,
      if (byName.containsKey('Food & Dining'))
        'Food & Dining': byName['Food & Dining']!,
      ...byName,
    };
    await seed(account, ordered);

    unawaited(RouteUtils.pushRoute(const InsightsPage()));
    expect(
      await pumpUntilFound(tester, find.text('Categorías principales')),
      isTrue,
      reason: 'insights figures not shown',
    );
    marker(
      'recurring section: ${find.text('Gastos recurrentes').evaluate().isNotEmpty}',
    );
    await shot(tester, '06_insights_figures');

    await tester.scrollUntilVisible(
      find.text('Pedir recomendaciones'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pedir recomendaciones'));
    final tips = await pumpUntilFound(
      tester,
      find.textContaining('Últimas recomendaciones'),
      timeout: const Duration(seconds: 90),
    );
    marker('gemini tips shown: $tips');
    await tester.scrollUntilVisible(
      find.textContaining('Últimas recomendaciones'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await shot(tester, '06_insights_tips');
    expect(tips, isTrue, reason: 'no Gemini recommendations');

    // Recategorize one transaction.
    final before = await query(
      "SELECT c.name AS category FROM transactions t JOIN categories c ON c.id = t.categoryID WHERE t.title = 'E2E-INS Uber al aeropuerto'",
    );
    marker('uber category before: ${before.first['category']}');
    await tester.scrollUntilVisible(
      find.text('Recategorizar transacciones'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Recategorizar transacciones'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Recategorizar transacciones'));
    final onRecategorize = await pumpUntilFound(
      tester,
      find.text('Proponer categorías'),
    );
    if (!onRecategorize) await shot(tester, '06_recategorize_not_opened');
    expect(onRecategorize, isTrue);
    await tester.enterText(find.byType(TextField).first, 'Uber al aeropuerto');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpFor(tester, const Duration(seconds: 2));
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpFor(tester, const Duration(seconds: 1));
    marker(
      'rows after the title filter: Uber=${find.text('E2E-INS Uber al aeropuerto').evaluate().length} Netflix=${find.text('E2E-INS Netflix').evaluate().length}',
    );
    await shot(tester, '06_recategorize_filtered');
    // The page lists ~40 filter chips before the buttons, which the lazy list builds only when scrolled to.
    await tester.scrollUntilVisible(
      find.text('Proponer categorías'),
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Proponer categorías'));
    final proposed = await pumpUntilFound(
      tester,
      find.textContaining('→'),
      timeout: const Duration(seconds: 90),
    );
    marker('proposal shown: $proposed');
    await shot(tester, '06_recategorize_proposal');
    expect(proposed, isTrue, reason: 'Gemini gave no category proposal');
    await tester.tap(find.text('Aplicar seleccionadas'));
    final applied = await pumpUntilFound(
      tester,
      find.textContaining('transacciones actualizadas'),
      timeout: const Duration(seconds: 30),
    );
    await shot(tester, '06_recategorize_applied');
    final after = await query(
      "SELECT c.name AS category FROM transactions t JOIN categories c ON c.id = t.categoryID WHERE t.title = 'E2E-INS Uber al aeropuerto'",
    );
    marker('uber category after: ${after.first['category']}');
    FlutterError.onError = previousOnError;
    while (tester.takeException() != null) {}
    marker(
      'BUG-05 paint errors during the flow: ${paintErrors.toSet().toList()}',
    );
    expect(applied, isTrue);
    expect(after.first['category'], isNot(before.first['category']));
    expect(
      paintErrors,
      isEmpty,
      reason: 'BUG-05: a PieChart repaint failed after recategorizing',
    );
  });
}
