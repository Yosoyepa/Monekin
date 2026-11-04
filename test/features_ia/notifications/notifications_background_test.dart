import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_service.dart';
import 'package:monekin/features_ia/insights/insights_service_impl.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notifications_background.dart';

import '../utils/consent_support.dart';
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

        await run();
        expect(notifier.shown, hasLength(1));

        fraction = 1.0;
        await run();
        expect(notifier.shown, hasLength(2));

        fraction = 1.25;
        await run();
        expect(notifier.shown, hasLength(2));
      },
    );

    // F-06: the lock screen must not show figures or budget names.
    test('the alert carries no digits, amounts or budget names', () async {
      for (final f in [0.80, 1.0]) {
        fraction = f;
        await run();
      }
      expect(notifier.shown, hasLength(2));
      for (final n in notifier.shown) {
        final text = '${n.title}\n${n.body}';
        expect(text, isNot(matches(RegExp(r'\d'))));
        expect(text, isNot(contains('Mercado')));
        expect(text, isNot(contains('%')));
        expect(text, isNot(contains(r'$')));
        expect(n.payload, isNull);
      }
    });

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
      title: 'You spent \$1,250,000 this week',
      body: 'Food took 40% of it. Try cooking at home on Tuesday.',
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
      expect(notifier.shown.single.channel, AlertChannel.weekly);
    });

    // F-06: the figures and the tip are read inside the app only.
    test('the notification carries nothing of the summary', () async {
      await run(monday);
      final n = notifier.shown.single;
      final text = '${n.title}\n${n.body}';
      expect(text, isNot(matches(RegExp(r'\d'))));
      expect(text, isNot(contains(summary.title)));
      expect(text, isNot(contains('Food')));
      expect(text, isNot(contains('cooking')));
    });

    // The background run is calculated on the phone: with the AI allowed and configured it sends nothing.
    test('the background run makes no AI request', () async {
      await useTestConsent();
      final client = RecordingAiClient('{"tips":["x"]}');
      AiService.debugClientOverride = client;
      addTearDown(() => AiService.debugClientOverride = null);
      InsightsService.instance = InsightsServiceImpl(
        loadExpenses: (start, end) async => [
          InsightTransaction(
            title: 'Almuerzo',
            amount: 30000,
            date: DateTime(2026, 10, 30),
            categoryId: 'food',
            categoryName: 'Comida',
          ),
        ],
        preferredCurrency: () async => const CurrencyInDB(
          code: 'COP',
          symbol: r'$',
          name: 'Peso',
          decimalPlaces: 0,
          isDefault: true,
          type: 0,
        ),
        now: () => monday,
      );

      await run(monday);

      expect(notifier.shown, hasLength(1));
      expect(client.requests, isEmpty);
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
