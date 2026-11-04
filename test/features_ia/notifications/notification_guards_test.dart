import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/notifications/notification_guards.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';

void main() {
  group('notice fingerprint', () {
    final at = DateTime(2026, 11, 4, 10, 15, 20, 123).millisecondsSinceEpoch;
    final clock = DateTime(2026, 11, 4, 10, 16);

    String fp({
      String package = 'com.nequi.MobileApp',
      int? id = 7,
      String title = 'Nequi',
      String content = 'Pagaste \$45.900 en EXITO',
      int? postedAtMs,
      DateTime? now,
    }) => noticeFingerprint(
      package,
      id,
      title,
      content,
      postedAtMs ?? at,
      now: now ?? clock,
    );

    test(
      'the same notification has the same fingerprint, ignoring case and spaces',
      () {
        expect(
          fp(),
          fp(title: 'NEQUI', content: '  pagaste  \$45.900\nen exito '),
        );
      },
    );

    test('another id, text, app or exact post time is another notice', () {
      final base = fp();
      expect(fp(id: 8), isNot(base));
      expect(fp(content: 'Pagaste \$45.900 en D1'), isNot(base));
      expect(fp(package: 'com.nu.production'), isNot(base));
      expect(fp(postedAtMs: at + 1), isNot(base));
    });

    test('the clock does not matter when the system gave the post time', () {
      expect(fp(now: clock.add(const Duration(hours: 5))), fp());
    });

    test('a missing notification id still gives a fingerprint', () {
      expect(fp(id: null), startsWith('com.nequi.MobileApp||'));
      expect(fp(id: null), isNot(fp(id: 0)));
    });

    group('without post time', () {
      const text = 'Compraste \$32.500 en UBER el 15/09/2026 a las 20:35.';

      test('uses the date and time of the text, whatever the clock says', () {
        final a = fp(content: text, postedAtMs: 0);
        expect(
          fp(
            content: text,
            postedAtMs: 0,
            now: clock.add(const Duration(days: 1)),
          ),
          a,
        );
        expect(
          fp(content: text.replaceFirst('20:35', '20:36'), postedAtMs: 0),
          isNot(a),
        );
      });

      test('falls back to the minute of the clock', () {
        final a = fp(postedAtMs: 0);
        expect(
          fp(postedAtMs: 0, now: clock.add(const Duration(seconds: 30))),
          a,
        );
        expect(
          fp(postedAtMs: 0, now: clock.add(const Duration(minutes: 1))),
          isNot(a),
        );
      });
    });
  });

  group('budget alert level', () {
    test('79 % does not warn', () => expect(budgetAlertFor(0.79, 0), isNull));
    test(
      '80 % warns',
      () => expect(budgetAlertFor(0.80, 0), BudgetAlertLevel.warning),
    );
    test(
      '99 % still only warns',
      () => expect(budgetAlertFor(0.99, 0), BudgetAlertLevel.warning),
    );
    test(
      '100 % is exceeded',
      () => expect(budgetAlertFor(1.0, 0), BudgetAlertLevel.exceeded),
    );
    test('jumping from 50 % to 130 % is exceeded, not a warning', () {
      expect(budgetAlertFor(1.3, 0), BudgetAlertLevel.exceeded);
    });
    test('a level already notified is not repeated', () {
      expect(budgetAlertFor(0.85, 80), isNull);
      expect(budgetAlertFor(1.2, 100), isNull);
    });
    test('after the warning, reaching 100 % still notifies', () {
      expect(budgetAlertFor(1.0, 80), BudgetAlertLevel.exceeded);
    });
    test('0.8 computed from sums is not missed by float error', () {
      expect(
        budgetAlertFor(80000 / 100000 - 1e-12, 0),
        BudgetAlertLevel.warning,
      );
    });
  });

  group('budget alert tracker', () {
    final start = DateTime(2026, 11, 1);

    test(
      'notifies once per level and does not repeat it the same day',
      () async {
        final tracker = BudgetAlertTracker(
          NotificationsPrefs(MemoryKeyValueStore()),
        );
        Future<BudgetAlertLevel?> check(double f) => tracker.evaluate(
          budgetId: 'b1',
          periodStart: start,
          fractionSpent: f,
        );

        expect(await check(0.79), isNull);
        expect(await check(0.80), BudgetAlertLevel.warning);
        expect(await check(0.80), isNull);
        expect(await check(0.92), isNull);
        expect(await check(1.00), BudgetAlertLevel.exceeded);
        expect(await check(1.00), isNull);
        expect(await check(1.40), isNull);
      },
    );

    test('budgets are independent', () async {
      final tracker = BudgetAlertTracker(
        NotificationsPrefs(MemoryKeyValueStore()),
      );
      expect(
        await tracker.evaluate(
          budgetId: 'b1',
          periodStart: start,
          fractionSpent: 0.9,
        ),
        BudgetAlertLevel.warning,
      );
      expect(
        await tracker.evaluate(
          budgetId: 'b2',
          periodStart: start,
          fractionSpent: 0.9,
        ),
        BudgetAlertLevel.warning,
      );
    });

    test('a new period notifies again', () async {
      final tracker = BudgetAlertTracker(
        NotificationsPrefs(MemoryKeyValueStore()),
      );
      await tracker.evaluate(
        budgetId: 'b1',
        periodStart: start,
        fractionSpent: 1.1,
      );
      expect(
        await tracker.evaluate(
          budgetId: 'b1',
          periodStart: DateTime(2026, 12, 1),
          fractionSpent: 0.85,
        ),
        BudgetAlertLevel.warning,
      );
    });

    test('the state survives a new tracker over the same store', () async {
      final store = MemoryKeyValueStore();
      await BudgetAlertTracker(
        NotificationsPrefs(store),
      ).evaluate(budgetId: 'b1', periodStart: start, fractionSpent: 0.9);
      final again = await BudgetAlertTracker(
        NotificationsPrefs(store),
      ).evaluate(budgetId: 'b1', periodStart: start, fractionSpent: 0.9);
      expect(again, isNull);
    });
  });
}
