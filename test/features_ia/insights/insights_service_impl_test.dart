import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_service_impl.dart';

import '../utils/consent_support.dart';

class _FakeClient implements AiClient {
  _FakeClient({this.reply = ''});

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
  // Last seven days: Oct 29 – Nov 4. Week before: Oct 22 – Oct 28.
  final now = DateTime(2026, 11, 4, 15, 30);
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
      date: DateTime(2026, 11, 2),
      categoryId: 'food',
      categoryName: 'Comida',
    ),
    InsightTransaction(
      title: 'Mercado',
      amount: 70000,
      date: DateTime(2026, 11, 3),
      categoryId: 'food',
      categoryName: 'Comida',
    ),
    InsightTransaction(
      title: 'Bus',
      amount: 5000,
      date: DateTime(2026, 10, 30),
      categoryId: 'transport',
      categoryName: 'Transporte',
    ),
    InsightTransaction(
      title: 'Mercado',
      amount: 50000,
      date: DateTime(2026, 10, 25),
      categoryId: 'food',
      categoryName: 'Comida',
    ),
  ];

  late List<(DateTime, DateTime)> requested;

  InsightsServiceImpl service({List<InsightTransaction>? data}) =>
      InsightsServiceImpl(
        loadExpenses: (start, end) async {
          requested.add((start, end));
          return data ?? expenses;
        },
        preferredCurrency: () async => currency,
        now: () => now,
      );

  setUp(() async {
    await useTestConsent();
    requested = [];
    AiService.debugClientOverride = null;
  });

  tearDown(() {
    AiService.debugClientOverride = null;
  });

  test(
    'adds the comparison and the local recommendation for the top category',
    () async {
      final summary = await service().weeklySummary();

      expect(summary, isNotNull);
      expect(summary!.body, contains('105'));
      expect(summary.body, contains('110%'));
      expect(summary.body, contains('Comida'));
      expect(summary.body, contains('95%'));
    },
  );

  test('says when the week cost less than the one before', () async {
    final summary = await service(
      data: [
        InsightTransaction(
          title: 'Almuerzo',
          amount: 20000,
          date: DateTime(2026, 11, 2),
          categoryId: 'food',
          categoryName: 'Comida',
        ),
        InsightTransaction(
          title: 'Mercado',
          amount: 80000,
          date: DateTime(2026, 10, 25),
          categoryId: 'food',
          categoryName: 'Comida',
        ),
      ],
    ).weeklySummary();

    expect(summary!.body, contains('75%'));
    expect(summary.body, contains('less than'));
  });

  test('reads the last seven days and the week before them', () async {
    await service().weeklySummary();

    expect(requested.single, (DateTime(2026, 10, 22), DateTime(2026, 11, 5)));
  });

  test(
    'it never calls the AI, even when it is configured and allowed',
    () async {
      final client = _FakeClient(
        reply: jsonEncode({
          'tips': ['Reduce los gastos en Comida'],
        }),
      );
      AiService.debugClientOverride = client;

      final summary = await service().weeklySummary();

      expect(summary!.body, isNot(contains('Reduce los gastos')));
      expect(summary.body, contains('95%'));
      expect(client.calls, isEmpty);
    },
  );
  test('returns null when nothing was spent in the last seven days', () async {
    final summary = await service(
      data: [
        InsightTransaction(
          title: 'Viejo',
          amount: 9000,
          date: DateTime(2026, 10, 1),
          categoryId: 'food',
          categoryName: 'Comida',
        ),
      ],
    ).weeklySummary();

    expect(summary, isNull);
  });
}
