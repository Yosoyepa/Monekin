import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_data.dart';
import 'package:monekin/features_ia/insights/insights_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class _FakeClient implements AiClient {
  _FakeClient(this.reply);

  final String reply;
  final List<List<AiMessage>> calls = [];

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls.add(messages);
    return AiResult(text: reply);
  }

  @override
  Future<List<String>> listModels() async => const [];
}

void main() {
  // Dated in this month and the previous one, so the page finds them whenever the test runs.
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 2);
  final lastMonth = DateTime(now.year, now.month - 1, 5);
  const currency = CurrencyInDB(
    code: 'COP',
    symbol: r'$',
    name: 'Peso colombiano',
    decimalPlaces: 0,
    isDefault: true,
    type: 0,
  );
  final expenses = [
    InsightTransaction(
      title: 'Almuerzo',
      amount: 30000,
      date: thisMonth,
      categoryId: 'food',
      categoryName: 'Comida',
    ),
    InsightTransaction(
      title: 'Mercado',
      amount: 70000,
      date: thisMonth,
      categoryId: 'food',
      categoryName: 'Comida',
    ),
    InsightTransaction(
      title: 'Concierto',
      amount: 400000,
      date: thisMonth,
      categoryId: 'leisure',
      categoryName: 'Ocio',
    ),
    InsightTransaction(
      title: 'Streaming',
      amount: 35000,
      date: thisMonth,
      categoryId: 'leisure',
      categoryName: 'Ocio',
    ),
    InsightTransaction(
      title: 'Streaming',
      amount: 35000,
      date: lastMonth,
      categoryId: 'leisure',
      categoryName: 'Ocio',
    ),
    InsightTransaction(
      title: 'Cine',
      amount: 30000,
      date: lastMonth,
      categoryId: 'leisure',
      categoryName: 'Ocio',
    ),
    InsightTransaction(
      title: 'Mercado',
      amount: 50000,
      date: lastMonth,
      categoryId: 'food',
      categoryName: 'Comida',
    ),
  ];

  SavedTips? stored;

  setUp(() {
    stored = null;
    InsightsData.debugOverride = InsightsData(
      loadExpenses: (start, end) async => expenses,
      preferredCurrency: () async => currency,
      loadLastTips: () async => null,
      saveLastTips: (saved) async => stored = saved,
    );
    AiService.debugClientOverride = null;
  });

  tearDown(() {
    InsightsData.debugOverride = null;
    AiService.debugClientOverride = null;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // A tall screen, so every row and button is built without scrolling.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(ChanchiMascot.preload);
    await tester.pumpWidget(const MaterialApp(home: InsightsPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('shows top categories, recurring and unusual expenses', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('Comida'), findsOneWidget);
    expect(find.textContaining('Streaming'), findsOneWidget);
    expect(find.textContaining('Concierto'), findsOneWidget);
  });

  testWidgets(
    'sends only aggregates to the AI and shows the three tips it returns',
    (tester) async {
      final client = _FakeClient(
        jsonEncode({
          'tips': ['Uno', 'Dos', 'Tres'],
        }),
      );
      AiService.debugClientOverride = client;
      await pumpPage(tester);

      await tester.tap(find.text(t.ia_insights.get_tips));
      await tester.pumpAndSettle();

      expect(client.calls, hasLength(1));
      expect(client.calls.single.last.text, isNot(contains('Almuerzo')));
      expect(find.text('Uno'), findsOneWidget);
      expect(find.text('Tres'), findsOneWidget);
      expect(stored?.tips, ['Uno', 'Dos', 'Tres']);
    },
  );

  testWidgets('asks to set up a provider when none is configured', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text(t.ia_insights.get_tips));
    await tester.pumpAndSettle();

    expect(find.text(t.ia_insights.not_configured), findsOneWidget);
    expect(stored, isNull);
  });
}
