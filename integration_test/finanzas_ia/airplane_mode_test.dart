// Flow 8 of the Finanzas IA emulator E2E (T002): with airplane mode on the app opens, a manual expense is
// registered, and the AI features fail with a clear message instead of hanging.
// The host script (docs/e2e/run_e2e.ps1) switches airplane mode on and off on the emulator.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/core/utils/unique_app_widgets_keys.dart';
import 'package:monekin/core/utils/uuid.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/receipts/receipt_capture.dart';
import 'package:monekin/features_ia/settings/ai_settings_page.dart';

import 'support/e2e_support.dart';

Future<List<Map<String, Object?>>> query(String sql) async {
  final rows = await AppDB.instance.customSelect(sql).get();
  return [for (final r in rows) r.data];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flow 8: airplane mode', (tester) async {
    addTearDown(() => marker('airplane-off'));
    await bootApp(tester);
    final service = AiService.instance as AiServiceImpl;
    if (!await service.isConfigured()) {
      await service.saveConfig(aiPresets[AiProviderId.gemini]!);
      await service.saveKey(geminiKey);
    }
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

    marker('airplane-on');
    await pumpFor(tester, const Duration(seconds: 8));
    await shot(tester, '08_airplane_home');

    // A manual expense is stored without any network.
    final before =
        (await query('SELECT COUNT(*) AS n FROM transactions')).first['n']
            as int;
    await TransactionService.instance.insertTransaction(
      TransactionInDB(
        id: generateUUID(),
        date: DateTime.now().subtract(const Duration(hours: 1)),
        accountID: account,
        value: -9900,
        title: 'E2E-OFFLINE Gasto manual',
        type: TransactionType.expense,
        categoryID: category,
        isHidden: false,
      ),
    );
    final after =
        (await query('SELECT COUNT(*) AS n FROM transactions')).first['n']
            as int;
    marker('manual expense offline: before=$before after=$after');
    expect(after, before + 1);
    await pumpFor(tester, const Duration(seconds: 2));
    await shot(tester, '08_airplane_manual_expense');

    // "Probar conexión" answers with a clear error within the timeout.
    unawaited(RouteUtils.pushRoute(const AiSettingsPage()));
    expect(
      await pumpUntilFound(tester, find.byKey(const ValueKey('ai-key'))),
      isTrue,
    );
    final started = DateTime.now();
    await tester.tap(find.textContaining('Probar conex'));
    final clearError = await pumpUntilFound(
      tester,
      find.textContaining('No se pudo conectar'),
      timeout: const Duration(seconds: 70),
    );
    marker(
      'test-connection offline: error=$clearError after ${DateTime.now().difference(started).inSeconds}s',
    );
    await shot(tester, '08_airplane_ai_settings_error');
    expect(
      clearError,
      isTrue,
      reason: 'no clear offline error in the AI settings',
    );
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    await pumpFor(tester, const Duration(seconds: 1));

    // A receipt read without network ends (no endless spinner) and says why.
    debugReceiptPhotosOverride = () async => [
      XFile('$fixturesDir/${receiptFixtures[1]}'),
    ];
    unawaited(startReceiptCapture(navigatorKey.currentContext!));
    final receiptStarted = DateTime.now();
    final reviewOrError = await pumpUntilFound(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            ((w.data ?? '').contains('Revisar transacciones') ||
                (w.data ?? '').toLowerCase().contains('conex') ||
                (w.data ?? '').toLowerCase().contains('red')),
      ),
      timeout: const Duration(seconds: 90),
    );
    marker(
      'receipt offline: finished=$reviewOrError after ${DateTime.now().difference(receiptStarted).inSeconds}s',
    );
    await shot(tester, '08_airplane_receipt');
    debugReceiptPhotosOverride = null;
    expect(reviewOrError, isTrue, reason: 'the receipt read hung offline');
  });
}
