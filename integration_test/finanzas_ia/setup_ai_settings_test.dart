// Flows 1 and 2 of the Finanzas IA emulator E2E (T002): first use and AI settings through the UI.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/cards/card_map.dart';
import 'package:monekin/features_ia/settings/ai_settings_page.dart';

import 'support/e2e_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flow 1: accounts in COP and the card map', (tester) async {
    await bootApp(tester);
    final cash = await ensureAccount(
      'Efectivo',
      iniValue: 500000,
      date: DateTime(2026, 1, 1),
    );
    final bank = await ensureAccount(
      'Bancolombia Ahorros',
      iniValue: 2350000,
      date: DateTime(2026, 1, 1),
    );
    await ensureAccount('Nequi', iniValue: 350000, date: DateTime(2026, 1, 1));
    await CardMapService.instance.save({'9911': bank});
    expect(await CardMapService.instance.accountFor('9911'), bank);
    expect(cash, isNotEmpty);
    await shot(tester, '01_home_with_accounts');
  });

  testWidgets('flow 2: AI settings by the UI, test connection, model', (
    tester,
  ) async {
    expect(geminiKey, isNotEmpty, reason: 'run with --dart-define-from-file');
    await bootApp(tester);
    unawaited(RouteUtils.pushRoute(const AiSettingsPage()));
    expect(
      await pumpUntilFound(tester, find.byKey(const ValueKey('ai-key'))),
      isTrue,
    );
    await shot(tester, '02_ai_settings_empty');

    expect(find.text('Gemini'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('ai-key')), geminiKey);
    final model = find.widgetWithText(TextField, 'gemini-flash-lite-latest');
    expect(model, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-save')));
    await pumpFor(tester, const Duration(seconds: 2));

    await tester.tap(find.textContaining('Probar conex'));
    final ok = await pumpUntilFound(
      tester,
      find.textContaining('correcta'),
      timeout: const Duration(seconds: 60),
    );
    await shot(tester, '02_ai_settings_connected');
    expect(ok, isTrue);
    expect(await AiService.instance.isConfigured(), isTrue);
  });
}
