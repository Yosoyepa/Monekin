import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_prompt.dart';

const _names = {
  'food': 'Comida',
  'transport': 'Transporte',
  'gifts': 'Regalos',
  'leisure': 'Ocio',
};

InsightTransaction _tx(
  String title,
  double amount,
  DateTime date,
  String categoryId,
) => InsightTransaction(
  title: title,
  amount: amount,
  date: date,
  categoryId: categoryId,
  categoryName: _names[categoryId]!,
);

void main() {
  final aggregates = computeInsightsAggregates(
    start: DateTime(2026, 11, 1),
    end: DateTime(2026, 12, 1),
    transactions: [
      _tx('Regalo viejo', 1000, DateTime(2026, 10, 5), 'gifts'),
      _tx('Regalo viejo 2', 1000, DateTime(2026, 10, 6), 'gifts'),
      _tx('Netflix', 45, DateTime(2026, 10, 5), 'leisure'),
      _tx('Joyería Secreta', 7913.5, DateTime(2026, 11, 12), 'gifts'),
      _tx('Detalle', 50, DateTime(2026, 11, 13), 'gifts'),
      _tx('Súper Local', 300, DateTime(2026, 11, 3), 'food'),
      _tx('Taxi Ruta 7', 120, DateTime(2026, 11, 4), 'transport'),
      _tx('Netflix', 45, DateTime(2026, 11, 5), 'leisure'),
    ],
  );
  final messages = buildRecommendationMessages(
    aggregates,
    currency: 'COP',
    language: 'Spanish',
  );

  test(
    'sends a system message with the tips format and a user message with the aggregates',
    () {
      expect(messages.map((m) => m.role), ['system', 'user']);
      expect(messages.first.text, contains('"tips"'));
      expect(messages.first.text, contains('Spanish'));
    },
  );

  test('never sends individual transactions', () {
    final payload = messages.last.text;

    for (final title in [
      'Regalo viejo',
      'Netflix',
      'Joyería Secreta',
      'Detalle',
      'Súper Local',
      'Taxi Ruta 7',
    ]) {
      expect(payload, isNot(contains(title)));
    }
    expect(payload, isNot(contains('7913.5')));
    expect(payload, isNot(contains('"title"')));
  });

  test('carries totals, top categories, recurring and anomaly counts', () {
    final payload = jsonDecode(messages.last.text) as Map<String, dynamic>;

    expect(payload['currency'], 'COP');
    expect(payload['totalExpenses'], 8428.5);
    expect(payload['previousPeriodExpenses'], 2045);
    expect(payload['recurring'], {'count': 1, 'total': 45});
    expect(payload['anomalies'], {
      'count': 1,
      'categories': ['Regalos'],
    });

    final topCategories = payload['topCategories'] as List;
    expect(topCategories.first['name'], 'Regalos');
    expect(topCategories.first['amount'], 7963.5);
    expect(topCategories.first['sharePercent'] as num, closeTo(94.48, 0.01));
  });
}
