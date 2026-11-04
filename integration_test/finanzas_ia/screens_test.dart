// Screenshots of the new screens in light mode (T002, round 2, flow 10): inbox, card map, AI settings, insights,
// notification settings, export page, Drive backup page and the «More» menu.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/core/utils/unique_app_widgets_keys.dart';
import 'package:monekin/app/settings/pages/backup/export_page.dart';
import 'package:monekin/features_ia/core/cards/card_map.dart';
import 'package:monekin/features_ia/core/cards/card_map_page.dart';
import 'package:monekin/features_ia/google/google_backup_page.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_page.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/insights/insights_page.dart';
import 'package:monekin/features_ia/notifications/notifications_settings_page.dart';
import 'package:monekin/features_ia/settings/ai_settings_page.dart';

import 'support/e2e_support.dart';

Future<void> visit(
  WidgetTester tester,
  Widget page,
  String name, {
  Finder? ready,
}) async {
  unawaited(RouteUtils.pushRoute(page));
  await pumpFor(tester, const Duration(seconds: 4));
  if (ready != null) await pumpUntilFound(tester, ready);
  await shot(tester, name);
  navigatorKey.currentState?.popUntil((route) => route.isFirst);
  await pumpFor(tester, const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flow 10: screens of the new features in light mode', (
    tester,
  ) async {
    await bootApp(tester);
    await resetData();
    await ensureAiConfigured();
    final bank = await ensureAccount(
      'Bancolombia Ahorros',
      iniValue: 2350000,
      date: DateTime(2026, 1, 1),
    );
    await ensureAccount(
      'Efectivo',
      iniValue: 500000,
      date: DateTime(2026, 1, 1),
    );
    await CardMapService.instance.save({'9911': bank});
    for (final item in [
      ('UBER RIDES', 32500.0),
      ('EXITO', 45900.0),
      ('FARMATODO', 18200.0),
    ]) {
      await InboxService.instance.addItem(
        InboxDraft(
          source: InboxSource.notification,
          sourceRef: 'com.android.shell',
          rawText: 'Bancolombia ${item.$1} \$${item.$2}',
          proposals: [
            ProposedTransaction(
              date: DateTime.now(),
              title: item.$1,
              amount: item.$2,
            ),
          ],
        ),
      );
    }
    await shot(tester, 'R2_10_home');
    await visit(tester, const InboxPage(), 'R2_10_inbox');
    await visit(tester, const CardMapPage(), 'R2_10_card_map');
    await visit(tester, const AiSettingsPage(), 'R2_10_ai_settings');
    await visit(tester, const InsightsPage(), 'R2_10_insights');
    await visit(
      tester,
      const NotificationsSettingsPage(),
      'R2_10_notifications_settings',
    );
    await visit(tester, const ExportDataPage(), 'R2_10_export');
    await visit(tester, const GoogleBackupPage(), 'R2_10_google_drive');
  });
}
