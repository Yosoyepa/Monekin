import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notifications_settings_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:path/path.dart' as p;

const _damaged = '{"budget_alert_state":"{\\"b1|2026-1';

void main() {
  late Directory dir;
  late File file;
  late NotificationsPrefs prefs;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('x-slayer/notifications_channel'),
          (call) async => call.method == 'isPermissionGranted' ? false : null,
        );
    dir = Directory.systemTemp.createTempSync('finanzas_settings_page_');
    file = File(p.join(dir.path, 'finanzas_notifications.json'))
      ..writeAsStringSync(_damaged);
    prefs = NotificationsPrefs(FileKeyValueStore(() async => file));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('x-slayer/notifications_channel'),
          null,
        );
    dir.deleteSync(recursive: true);
  });

  // The page reads a real file, which needs real time.
  Future<void> waitFor(WidgetTester tester, Finder finder) =>
      tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('Not found: $finder');
      });

  Future<void> openPage(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(home: NotificationsSettingsPage(prefs: prefs)),
      ),
    );
    await waitFor(tester, find.byKey(const ValueKey('notifications-reset')));
  }

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
}
