import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/utils/unique_app_widgets_keys.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notifications_settings_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:path/path.dart' as p;
import '../utils/temp_dir.dart';

const _damaged = '{"budget_alert_state":"{\\"b1|2026-1';

bool readingOn(WidgetTester tester) => tester
    .widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Read bank notices'),
    )
    .value;

void main() {
  late Directory dir;
  late File file;
  late NotificationsPrefs prefs;
  var accessGranted = false;

  setUp(() {
    accessGranted = false;
    TestWidgetsFlutterBinding.ensureInitialized();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async =>
              call.method == 'requestNotificationsPermission' ? true : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('x-slayer/notifications_channel'),
          (call) async =>
              call.method == 'isPermissionGranted' ? accessGranted : null,
        );
    dir = Directory.systemTemp.createTempSync('finanzas_settings_page_');
    file = File(p.join(dir.path, 'finanzas_notifications.json'))
      ..writeAsStringSync(_damaged);
    prefs = NotificationsPrefs(FileKeyValueStore(() async => file));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('x-slayer/notifications_channel'),
          null,
        );
    await deleteTempDir(dir);
  });

  // The page reads a real file, which needs real time: up to 20 s on a busy machine.
  Future<void> waitFor(WidgetTester tester, Finder finder) =>
      tester.runAsync(() async {
        for (var i = 0; i < 400; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('Not found: $finder');
      });

  Future<void> openPage(
    WidgetTester tester, {
    Finder? until,
    Future<bool> Function()? openAppInfo,
  }) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          scaffoldMessengerKey: snackbarKey,
          home: NotificationsSettingsPage(
            prefs: prefs,
            openAppInfo: openAppInfo,
          ),
        ),
      ),
    );
    await waitFor(
      tester,
      until ?? find.byKey(const ValueKey('notifications-reset')),
    );
  }

  Future<void> waitGone(WidgetTester tester, Finder finder) =>
      tester.runAsync(() async {
        for (var i = 0; i < 400; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          if (finder.evaluate().isEmpty) return;
        }
        fail('Still found: $finder');
      });

  testWidgets('an unreadable file shows the problem and a reset button', (
    tester,
  ) async {
    await openPage(tester);

    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.text('Reset notification settings'), findsOneWidget);
    expect(find.text('Read bank notices'), findsNothing);
    expect(file.readAsStringSync(), _damaged);
  });

  testWidgets('cancelling the confirmation keeps the file', (tester) async {
    await openPage(tester);

    await tester.tap(find.byKey(const ValueKey('notifications-reset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notifications-reset-confirm')), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(file.readAsStringSync(), _damaged);
    expect(find.byKey(const ValueKey('notifications-reset')), findsOneWidget);
  });

  testWidgets('confirming replaces the file with the defaults', (tester) async {
    await openPage(tester);

    await tester.tap(find.byKey(const ValueKey('notifications-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notifications-reset-confirm')));
    await waitFor(tester, find.text('Read bank notices'));
    expect(find.byKey(const ValueKey('notifications-reset')), findsNothing);
    expect(file.readAsStringSync(), '{}');
    expect(File('${file.path}.corrupt').readAsStringSync(), _damaged);
  });

  testWidgets('the AI switch for notices is off and turning it on is saved', (
    tester,
  ) async {
    file.writeAsStringSync('{}');
    await openPage(tester, until: find.text('Read bank notices'));
    final aiSwitch = find.widgetWithText(
      SwitchListTile,
      'Use AI for notices the app cannot read',
    );

    expect(tester.widget<SwitchListTile>(aiSwitch).value, isFalse);
    expect(find.textContaining('no balances'), findsOneWidget);

    await tester.ensureVisible(aiSwitch);
    await tester.tap(aiSwitch);
    // The page writes the real file; it needs real time and pumps to finish.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (tester.widget<SwitchListTile>(aiSwitch).value) break;
    }

    expect(file.readAsStringSync(), contains('"ai_notices":"true"'));
    expect(tester.widget<SwitchListTile>(aiSwitch).value, isTrue);
  });

  testWidgets(
    'BUG-04: the add app dialog closes without a disposed controller',
    (tester) async {
      file.writeAsStringSync('{}');
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openPage(tester, until: find.text('Read bank notices'));
      final add = find.text('Add app');
      await tester.ensureVisible(add);

      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'com.banco.app');
      await tester.tap(find.text('OK'));
      // The page writes the real file; it needs real time and pumps to finish.
      for (var i = 0; i < 400; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (file.readAsStringSync().contains('com.banco.app')) break;
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(file.readAsStringSync(), contains('com.banco.app'));
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('BUG-04: cancelling the add app dialog raises nothing', (
    tester,
  ) async {
    file.writeAsStringSync('{}');
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openPage(tester, until: find.text('Read bank notices'));
    final add = find.text('Add app');
    await tester.ensureVisible(add);

    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('watching a messaging app warns that anyone can text you', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    file.writeAsStringSync('{}');
    await openPage(tester, until: find.text('Read bank notices'));
    final warning = find.byKey(
      const ValueKey('notifications-messaging-warning'),
    );

    expect(warning, findsNothing);

    await tester.tap(find.text('Add app'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'com.google.android.apps.messaging',
    );
    await tester.tap(find.text('OK'));
    await waitFor(tester, warning);

    expect(
      find.text(
        'Anyone can text you a message that looks like it came from your bank: always check the inbox before confirming.',
      ),
      findsOneWidget,
    );
    expect(
      file.readAsStringSync(),
      contains('com.google.android.apps.messaging'),
    );
  });

  testWidgets('a refused access shows the help card until it is granted', (
    tester,
  ) async {
    file.writeAsStringSync('{}');
    await openPage(tester, until: find.text('Read bank notices'));
    expect(
      find.byKey(const ValueKey('notifications-access-help')),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(SwitchListTile, 'Read bank notices'));
    await waitFor(
      tester,
      find.byKey(const ValueKey('notifications-access-help')),
    );

    expect(
      find.text('Does the switch look locked or say «Restricted setting»?'),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('notifications-access-app-info')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('notifications-access-retry')), findsOne);
    expect(readingOn(tester), isFalse);

    accessGranted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitGone(
      tester,
      find.byKey(const ValueKey('notifications-access-help')),
    );

    expect(readingOn(tester), isTrue);
  });

  testWidgets('the app info button calls the injected app settings opener', (
    tester,
  ) async {
    var opened = 0;
    // The help card sits below the fold of the default 800x600 test surface.
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    file.writeAsStringSync('{}');
    await openPage(
      tester,
      until: find.text('Read bank notices'),
      openAppInfo: () async {
        opened++;
        return true;
      },
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'Read bank notices'));
    await waitFor(
      tester,
      find.byKey(const ValueKey('notifications-access-app-info')),
    );

    await tester.tap(
      find.byKey(const ValueKey('notifications-access-app-info')),
    );

    expect(opened, 1);
  });
}
