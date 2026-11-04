// Flow 5 of the Finanzas IA emulator E2E (T002): bank notices read from the notification shade.
// The host script (docs/e2e/run_e2e.ps1) grants the listener access, posts the notices with
// `adb shell cmd notification post` (package com.android.shell) and taps the local notification.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notifications_feature.dart';

import 'support/e2e_support.dart';

Future<List<Map<String, Object?>>> query(String sql) async {
  final rows = await AppDB.instance.customSelect(sql).get();
  return [for (final r in rows) r.data];
}

Future<int> noticeItems() async =>
    (await query(
          "SELECT COUNT(*) AS n FROM aiInboxItems WHERE source='notification'",
        )).first['n']
        as int;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'flow 5b: notices -> inbox items and the local notification opens the review',
    (tester) async {
      await bootApp(tester);
      await resetData();
      // Notifications and notice fingerprints of earlier runs would hide the ones this test posts.
      await AppDB.instance.customStatement('DELETE FROM ai_notice_claims');
      await PluginLocalNotifier.instance.plugin.cancelAll();
      await ensureAccount(
        'Nequi',
        iniValue: 350000,
        date: DateTime(2026, 1, 1),
      );
      await ensureAccount(
        'Bancolombia Ahorros',
        iniValue: 2350000,
        date: DateTime(2026, 1, 1),
      );
      marker('grant-listener');
      await pumpFor(tester, const Duration(seconds: 6));
      await NotificationsPrefs.instance.setListenerEnabled(true);
      await NotificationsPrefs.instance.setWatchedPackages({
        ...await NotificationsPrefs.instance.watchedPackages(),
        'com.android.shell',
      });
      await syncNotificationFeatures();
      await pumpFor(tester, const Duration(seconds: 2));

      final before = await noticeItems();
      marker('post-notices');
      var after = before;
      final end = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(end) && after < before + 2) {
        await pumpFor(tester, const Duration(seconds: 2));
        after = await noticeItems();
      }
      marker('inbox notification items: before=$before after=$after');
      final items = await query(
        "SELECT sourceRef, status, substr(proposalsJson,1,260) AS p FROM aiInboxItems WHERE source='notification' ORDER BY createdAt DESC LIMIT 4",
      );
      for (final r in items) {
        marker('item ${r['sourceRef']} ${r['status']} ${r['p']}');
      }
      marker('dump-notifications');
      await pumpFor(tester, const Duration(seconds: 3));
      await shot(tester, '05_inbox_after_notices');
      expect(after, greaterThanOrEqualTo(before + 2));

      marker('tap-notification Nuevo movimiento por revisar');
      final opened = await pumpUntilFound(
        tester,
        find.text('Revisar transacciones'),
        timeout: const Duration(seconds: 25),
      );
      marker('local notification opened the review: $opened');
      await shot(tester, '05_notification_tap_result');
      expect(opened, isTrue);
    },
  );
}
