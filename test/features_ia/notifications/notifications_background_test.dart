import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
import 'package:monekin/features_ia/insights/insights_service.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notifications_background.dart';

import 'test_support.dart';

class _FakeInsights implements InsightsService {
  _FakeInsights(this.summary);

  final WeeklySummary? summary;
  int calls = 0;

  @override
  Future<WeeklySummary?> weeklySummary() async {
    calls++;
    return summary;
  }
}

void main() {
  late FakeNotifier notifier;
  late NotificationsPrefs prefs;

  setUp(() {
    notifier = FakeNotifier();
    prefs = NotificationsPrefs(MemoryKeyValueStore());
  });

  group('budget check', () {
    final start = DateTime(2026, 11, 1);
    var fraction = 0.0;
    Future<List<BudgetProgress>> budgets() async => [
      BudgetProgress(
        id: 'b1',
        name: 'Mercado',
        fraction: fraction,
        periodStart: start,
      ),
    ];
    Future<bool> run() =>
        runBudgetCheckTask(prefs: prefs, notifier: notifier, budgets: budgets);

    setUp(() => fraction = 0.0);

    test(
      '79 % shows nothing, 80 % warns, 100 % says exceeded, and nothing repeats',
      () async {
        fraction = 0.79;
        expect(await run(), isTrue);
        expect(notifier.shown, isEmpty);

        fraction = 0.80;
        await run();
        expect(notifier.shown, hasLength(1));
        expect(notifier.shown.last.channel, AlertChannel.budget);
        expect(notifier.shown.last.title, 'Budget at 80%');
        expect(
          notifier.shown.last.body,
          'Mercado: you have used 80% of the limit.',
        );

        await run();
        expect(notifier.shown, hasLength(1));

        fraction = 1.0;
        await run();
        expect(notifier.shown, hasLength(2));
        expect(notifier.shown.last.title, 'Budget exceeded');

        fraction = 1.25;
        await run();
        expect(notifier.shown, hasLength(2));
      },
    );

    test('with the alerts turned off nothing is shown', () async {
      await prefs.setBudgetAlertsEnabled(false);
      fraction = 1.5;
      await run();
      expect(notifier.shown, isEmpty);
    });
  });

  group('weekly summary', () {
    final monday = DateTime(2026, 11, 2, 9, 30);
    const summary = WeeklySummary(
      title: 'Your week',
      body: 'You spent less on food.',
    );

    Future<bool> run(DateTime now) =>
        runWeeklySummaryTask(prefs: prefs, notifier: notifier, now: () => now);

    setUp(() async {
      await prefs.setWeeklySummaryEnabled(true);
      InsightsService.instance = _FakeInsights(summary);
    });

    tearDown(() => InsightsService.instance = NotReadyInsightsService());

    test('shows the summary on Monday morning once', () async {
      await run(monday);
      await run(monday.add(const Duration(hours: 3)));
      expect(notifier.shown, hasLength(1));
      expect(notifier.shown.single.title, 'Your week');
      expect(notifier.shown.single.channel, AlertChannel.weekly);
    });

    test('shows again the next Monday', () async {
      await run(monday);
      await run(monday.add(const Duration(days: 7)));
      expect(notifier.shown, hasLength(2));
    });

    test('does not show on other days or before 9:00', () async {
      await run(DateTime(2026, 11, 3, 12));
      await run(DateTime(2026, 11, 2, 8, 59));
      expect(notifier.shown, isEmpty);
    });

    test('does nothing when the setting is off', () async {
      await prefs.setWeeklySummaryEnabled(false);
      final insights = _FakeInsights(summary);
      InsightsService.instance = insights;
      await run(monday);
      expect(notifier.shown, isEmpty);
      expect(insights.calls, 0);
    });

    test(
      'shows nothing when there is nothing to say, and tries again later',
      () async {
        final insights = _FakeInsights(null);
        InsightsService.instance = insights;
        await run(monday);
        expect(notifier.shown, isEmpty);
        InsightsService.instance = _FakeInsights(summary);
        await run(monday.add(const Duration(hours: 2)));
        expect(notifier.shown, hasLength(1));
      },
    );
  });

  group('dispatcher', () {
    test('task names are the contract of the other workers', () {
      expect(kTaskDailyReminder, 'finanzas.dailyReminder');
      expect(kTaskBudgetCheck, 'finanzas.budgetCheck');
      expect(kTaskWeeklySummary, 'finanzas.weeklySummary');
      expect(kTaskDriveBackup, 'finanzas.driveBackup');
    });

    test('an unknown task finishes without failing', () async {
      expect(await runBackgroundTask('finanzas.unknown'), isTrue);
    });
  });
}
