import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/notifications/notification_guards.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';

void main() {
  group('notice fingerprint', () {
    final at = DateTime(2026, 11, 4, 10, 15, 20).millisecondsSinceEpoch;

    test(
      'the same notice has the same fingerprint, ignoring case and spaces',
      () {
        final a = noticeFingerprint(
          'com.nequi.MobileApp',
          'Nequi',
          'Pagaste \$45.900 en EXITO',
          at,
        );
        final b = noticeFingerprint(
          'com.nequi.MobileApp',
          'NEQUI',
          '  pagaste  \$45.900\nen exito ',
          at + 25000,
        );
        expect(a, b);
        expect(a.length, 16);
      },
    );

    test('another minute, text or app is another notice', () {
      final base = noticeFingerprint(
        'com.nequi.MobileApp',
        'Nequi',
        'Pagaste \$45.900 en EXITO',
        at,
      );
      expect(
        noticeFingerprint(
          'com.nequi.MobileApp',
          'Nequi',
          'Pagaste \$45.900 en EXITO',
          at + 60000,
        ),
        isNot(base),
      );
      expect(
        noticeFingerprint(
          'com.nequi.MobileApp',
          'Nequi',
          'Pagaste \$45.900 en D1',
          at,
        ),
        isNot(base),
      );
      expect(
        noticeFingerprint(
          'com.nu.production',
          'Nequi',
          'Pagaste \$45.900 en EXITO',
          at,
        ),
        isNot(base),
      );
    });

    test('registerIfNew accepts a notice once', () async {
      final fp = NoticeFingerprints(NotificationsPrefs(MemoryKeyValueStore()));
      expect(await fp.registerIfNew('abc'), isTrue);
      expect(await fp.registerIfNew('abc'), isFalse);
      expect(await fp.registerIfNew('def'), isTrue);
    });

    test('forget lets the notice in again', () async {
      final fp = NoticeFingerprints(NotificationsPrefs(MemoryKeyValueStore()));
      await fp.registerIfNew('abc');
      await fp.forget('abc');
      expect(await fp.registerIfNew('abc'), isTrue);
    });

    test('old fingerprints are dropped after a week', () async {
      var now = DateTime(2026, 11, 1);
      final prefs = NotificationsPrefs(MemoryKeyValueStore());
      final fp = NoticeFingerprints(prefs, now: () => now);
      await fp.registerIfNew('abc');
      now = now.add(const Duration(days: 8));
      expect(await fp.registerIfNew('abc'), isTrue);
    });

    test('the list is capped, dropping the oldest', () async {
      var now = DateTime(2026, 11, 1);
      final prefs = NotificationsPrefs(MemoryKeyValueStore());
      final fp = NoticeFingerprints(prefs, now: () => now, maxEntries: 3);
      for (final k in ['a', 'b', 'c', 'd']) {
        await fp.registerIfNew(k);
        now = now.add(const Duration(minutes: 1));
      }
      final kept = (await prefs.fingerprints()).keys.toSet();
      expect(kept, {'b', 'c', 'd'});
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
