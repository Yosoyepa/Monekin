// Flow 5 of the Finanzas IA emulator E2E (T002): bank notices read from the notification shade.
// The host script (docs/e2e/run_e2e.ps1) grants the listener access, posts the notices with
// `adb shell cmd notification post` (package com.android.shell) and taps the local notification.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notifications_feature.dart';
import 'package:monekin/features_ia/notifications/notifications_settings_page.dart';

import 'support/e2e_support.dart';

Future<List<Map<String, Object?>>> query(String sql) async {
  final rows = await AppDB.instance.customSelect(sql).get();
  return [for (final r in rows) r.data];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flow 5: bank notices -> inbox items and a local notification', (
    tester,
  ) async {
    await bootApp(tester);
    await ensureAccount('Nequi', iniValue: 350000, date: DateTime(2026, 1, 1));
    await ensureAccount(
      'Bancolombia Ahorros',
      iniValue: 2350000,
      date: DateTime(2026, 1, 1),
    );

    marker('grant-listener');
    await pumpFor(tester, const Duration(seconds: 6));
    marker(
      'listener permission granted: ${await NotificationListenerService.isPermissionGranted()}',
    );

    unawaited(RouteUtils.pushRoute(const NotificationsSettingsPage()));
    expect(
      await pumpUntilFound(tester, find.text('Leer avisos del banco')),
      isTrue,
    );
    await shot(tester, '05_notifications_settings');

    await tester.tap(find.text('Leer avisos del banco'));
    await pumpFor(tester, const Duration(seconds: 3));
    expect(await NotificationsPrefs.instance.listenerEnabled(), isTrue);

    await tester.scrollUntilVisible(
      find.text('Añadir app'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Añadir app'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField).last, 'com.android.shell');
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 2));
    final watched = await NotificationsPrefs.instance.watchedPackages();
    marker('watched packages: ${watched.toList()..sort()}');
    expect(watched, contains('com.android.shell'));
    await shot(tester, '05_notifications_watched_app');
    await syncNotificationFeatures();

    final before =
        (await query(
              "SELECT COUNT(*) AS n FROM aiInboxItems WHERE source='notification'",
            )).first['n']
            as int;
    marker('post-notices');
    var after = before;
    final end = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(end) && after < before + 2) {
      await pumpFor(tester, const Duration(seconds: 2));
      after =
          (await query(
                "SELECT COUNT(*) AS n FROM aiInboxItems WHERE source='notification'",
              )).first['n']
              as int;
    }
    marker('inbox notification items: before=$before after=$after');
    final items = await query(
      "SELECT sourceRef, status, substr(proposalsJson,1,200) AS p FROM aiInboxItems WHERE source='notification'",
    );
    for (final r in items) {
      marker('item ${r['sourceRef']} ${r['status']} ${r['p']}');
    }
    marker('dump-notifications');
    await pumpFor(tester, const Duration(seconds: 3));
    await shot(tester, '05_inbox_after_notices');
    expect(after, greaterThanOrEqualTo(before + 2));

    // The local notification opens the review of the item.
    marker('tap-notification Nuevo gasto detectado');
    final opened = await pumpUntilFound(
      tester,
      find.text('Revisar transacciones'),
      timeout: const Duration(seconds: 25),
    );
    marker('local notification opened the review: $opened');
    await shot(tester, '05_notification_tap_result');
    expect(opened, isTrue);
  });
}
