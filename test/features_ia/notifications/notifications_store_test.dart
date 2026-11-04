import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notification_guards.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory dir;
  late File file;

  // Two stores over the same file stand for the main isolate and the workmanager one.
  FileKeyValueStore openStore() => FileKeyValueStore(() async => file);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('finanzas_store_');
    file = File(p.join(dir.path, 'finanzas_notifications.json'));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  RawNotice notice() => RawNotice(
    package: 'com.nequi.MobileApp',
    title: 'Nequi',
    content: 'Pagaste \$45.900 en EXITO',
    postedAtMs: DateTime(2026, 11, 4, 10, 15).millisecondsSinceEpoch,
  );

  NotificationProcessor processor(
    NotificationsPrefs prefs,
    FakeInbox inbox,
    FakeNotifier notifier,
  ) => NotificationProcessor(
    prefs: prefs,
    notifier: notifier,
    inbox: () => inbox,
    aiConfigured: () async => false,
    accountForCard: (_) async => null,
    parseAmount: testAmountParser,
    now: () => DateTime(2026, 11, 4, 10, 16),
  );

  test('two processors on the same notice leave one pending item', () async {
    final inbox = FakeInbox();
    final notifier = FakeNotifier();
    final a = processor(NotificationsPrefs(openStore()), inbox, notifier);
    final b = processor(NotificationsPrefs(openStore()), inbox, notifier);

    final outcomes = await Future.wait([
      a.process(notice()),
      b.process(notice()),
    ]);

    expect(
      outcomes,
      containsAll([NoticeOutcome.recognized, NoticeOutcome.duplicate]),
    );
    expect(inbox.drafts, hasLength(1));
    expect(notifier.shown, hasLength(1));
  });

  test('many writers in parallel do not lose any value', () async {
    final stores = [for (var i = 0; i < 4; i++) openStore()];
    await Future.wait([
      for (var i = 0; i < 40; i++)
        NotificationsPrefs(stores[i % 4]).editFingerprints((seen) {
          seen['fp$i'] = i;
        }),
    ]);
    final seen = await NotificationsPrefs(openStore()).fingerprints();
    expect(seen, hasLength(40));
  });

  test('a save leaves no temporary file behind', () async {
    await NotificationsPrefs(openStore()).setDailyReminderMinutes(480);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    expect(await NotificationsPrefs(openStore()).dailyReminderMinutes(), 480);
  });

  group('a truncated file', () {
    setUp(() => file.writeAsStringSync('{"budget_alert_state":"{\\"b1|2026-1'));

    test('is kept and read as an error, not as an empty file', () async {
      final prefs = NotificationsPrefs(openStore());
      await expectLater(
        prefs.budgetAlertState(),
        throwsA(isA<StoreCorruptedException>()),
      );
      await expectLater(
        prefs.setDailyReminderMinutes(60),
        throwsA(isA<StoreCorruptedException>()),
      );
      expect(file.readAsStringSync(), startsWith('{"budget_alert_state"'));
    });

    test('does not re-arm an alert already sent', () async {
      final notifier = FakeNotifier();
      await expectLater(
        NotificationsPrefs(openStore()).editBudgetAlertState((_) {}),
        throwsA(isA<StoreCorruptedException>()),
      );
      await expectLater(
        BudgetAlertTracker(NotificationsPrefs(openStore())).evaluate(
          budgetId: 'b1',
          periodStart: DateTime(2026, 11, 1),
          fractionSpent: 1.2,
          send: (_) async => notifier.show(
            id: 1,
            channel: AlertChannel.budget,
            title: 'x',
            body: 'y',
          ),
        ),
        throwsA(isA<StoreCorruptedException>()),
      );
      expect(notifier.shown, isEmpty);
    });
  });

  test('an alert whose sending failed stays due', () async {
    final prefs = NotificationsPrefs(MemoryKeyValueStore());
    final tracker = BudgetAlertTracker(prefs);
    Future<BudgetAlertLevel?> check(
      Future<void> Function(BudgetAlertLevel) send,
    ) => tracker.evaluate(
      budgetId: 'b1',
      periodStart: DateTime(2026, 11, 1),
      fractionSpent: 0.9,
      send: send,
    );

    await expectLater(
      check((_) async => throw StateError('offline')),
      throwsStateError,
    );
    expect(await prefs.budgetAlertState(), isEmpty);

    expect(await check((_) async {}), BudgetAlertLevel.warning);
    expect(await check((_) async {}), isNull);
  });
}
