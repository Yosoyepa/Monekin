// Flow 12 of the Finanzas IA emulator E2E (T002, round 2): a notice no template understands waits in the inbox
// «por leer con IA» and goes to the AI only when the user taps «Leer con IA».
// The host script (docs/e2e/run_e2e.ps1) grants the listener access, posts the notice and taps the local notification.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
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

  testWidgets('flow 12: unknown notice waits for the AI and is read on tap', (
    tester,
  ) async {
    await bootApp(tester);
    await resetData();
    await ensureAiConfigured();
    await resetConsent();
    final counting = await CountingAiClient.install();
    addTearDown(CountingAiClient.uninstall);
    await NotificationsPrefs.instance.saveFingerprints({});
    await PluginLocalNotifier.instance.plugin.cancelAll();
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
    await NotificationsPrefs.instance.setAiNoticesEnabled(false);

    // The «AI for unknown notices» switch, by the settings page.
    unawaited(RouteUtils.pushRoute(const NotificationsSettingsPage()));
    expect(
      await pumpUntilFound(
        tester,
        find.text('Usar la IA con los avisos que la app no entiende'),
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Usar la IA con los avisos que la app no entiende'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await shot(tester, 'R2_12_settings_ai_notices_off');
    await tester.tap(
      find.text('Usar la IA con los avisos que la app no entiende'),
    );
    await pumpFor(tester, const Duration(seconds: 2));
    expect(await NotificationsPrefs.instance.aiNoticesEnabled(), isTrue);
    await shot(tester, 'R2_12_settings_ai_notices_on');
    Navigator.of(tester.element(find.byType(NotificationsSettingsPage))).pop();
    await pumpFor(tester, const Duration(seconds: 1));
    await syncNotificationFeatures();
    await pumpFor(tester, const Duration(seconds: 2));

    marker('post-unknown-notice');
    var items = <Map<String, Object?>>[];
    final end = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(end) && items.isEmpty) {
      await pumpFor(tester, const Duration(seconds: 2));
      items = await query(
        "SELECT id, status, proposalsJson, note FROM aiInboxItems WHERE source='notification' ORDER BY createdAt DESC",
      );
    }
    expect(
      items,
      isNotEmpty,
      reason: 'the unknown notice never reached the inbox',
    );
    await pumpFor(tester, const Duration(seconds: 10));
    final copies = await query(
      "SELECT id, createdAt FROM aiInboxItems WHERE rawText LIKE '%LIBRERIA%'",
    );
    marker(
      'items for the one unknown notice, before any tap: ${copies.length} $copies',
    );
    final waiting = items.first;
    marker(
      'unknown notice item: status=${waiting['status']} proposals=${waiting['proposalsJson']} note=${waiting['note']}',
    );
    expect(
      (jsonDecode('${waiting['proposalsJson']}') as Map)['proposals'],
      isEmpty,
    );
    expect(
      counting.calls,
      0,
      reason: 'the AI was called before the user tapped «Leer con IA»',
    );

    marker('tap-notification Nuevo movimiento por revisar');
    expect(
      await pumpUntilFound(
        tester,
        find.byKey(const Key('inbox-ai-notice')),
        timeout: const Duration(seconds: 30),
      ),
      isTrue,
      reason: 'the review does not show the «por leer con IA» card',
    );
    expect(find.text('Aviso por leer con IA'), findsOneWidget);
    final sentence =
        (tester.widget(find.byKey(const Key('inbox-ai-text')))
                as SelectableText)
            .data ??
        '';
    marker('sentence that would be sent: "$sentence"');
    expect(
      sentence,
      isNot(contains('1234')),
      reason: 'the card must hide the card number',
    );
    await shot(tester, 'R2_12_notice_waiting_for_ai');
    expect(counting.calls, 0);

    // Decline first: nothing is sent.
    await tester.tap(find.byKey(const Key('inbox-read-ai')));
    await declineConsent(tester, shotName: 'R2_12_consent_notice');
    await pumpFor(tester, const Duration(seconds: 2));
    expect(
      counting.calls,
      0,
      reason: 'declining the consent still sent something',
    );
    expect(find.byKey(const Key('inbox-ai-notice')), findsOneWidget);

    // Accept: the sentence is read.
    await tester.tap(find.byKey(const Key('inbox-read-ai')));
    await acceptConsent(tester);
    // The card goes away once the AI answered (proposal, «not money» or «unclear»): wait for the item to change.
    // The notice can be in the inbox twice (see the marker above); the one the review opened is the one that is read.
    const readSql =
        "SELECT id, proposalsJson, note FROM aiInboxItems WHERE rawText LIKE '%LIBRERIA%' AND proposalsJson LIKE '%\"title\"%'";
    var readRows = <Map<String, Object?>>[];
    final readEnd = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(readEnd) && readRows.isEmpty) {
      await pumpFor(tester, const Duration(seconds: 2));
      readRows = await query(readSql);
    }
    await pumpFor(tester, const Duration(seconds: 2));
    marker(
      'read with AI: calls=${counting.calls} items with a proposal=${readRows.length} card gone=${find.byKey(const Key('inbox-ai-notice')).evaluate().isEmpty}',
    );
    await shot(tester, 'R2_12_notice_read');
    final titleField = find.byKey(const Key('inbox-title-0'));
    final shownTitle = titleField.evaluate().isEmpty
        ? null
        : tester.widget<TextField>(titleField).controller?.text;
    marker('review row title after reading: $shownTitle');
    expect(counting.calls, 1, reason: 'exactly one AI call expected');
    expect(
      readRows,
      isNotEmpty,
      reason: 'the AI read did not leave a proposal in the item',
    );
    expect(shownTitle, 'LIBRERIA NACIONAL');
    // Inbox duplicates are reported by the marker above (BUG-08), not asserted here.
  });
}
