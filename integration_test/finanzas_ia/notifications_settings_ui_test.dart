// Flow 5a of the Finanzas IA emulator E2E (T002): the notification settings page, through the UI.
// Kept in its own file (own app process): closing the add-app dialog raises framework errors in debug
// builds (BUG-04) that would otherwise poison the tests that run after it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notifications_settings_page.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import 'support/e2e_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('flow 5a: settings page turns the reader on and adds a watched app', (
    tester,
  ) async {
    await bootApp(tester);
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
    // BUG-04: closing this dialog disposes its controller while the route still animates, so debug
    // builds assert. Collect those errors here instead of failing the whole test, and report them.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.ensureVisible(find.text('Añadir app'));
    await pumpFor(tester, const Duration(seconds: 1));
    final dialogErrors = <String>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = (details) =>
        dialogErrors.add(details.exceptionAsString().split('\n').first);
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

    await pumpFor(tester, const Duration(seconds: 4));
    FlutterError.onError = previousOnError;
    while (tester.takeException() != null) {}
    marker(
      'BUG-04 framework errors while closing the add-app dialog: ${dialogErrors.length} ${dialogErrors.toSet().toList()}',
    );
    expect(
      dialogErrors,
      isEmpty,
      reason:
          'BUG-04: the add-app dialog disposes its controller while closing',
    );
  });
}
