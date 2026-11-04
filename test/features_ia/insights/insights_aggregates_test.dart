import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';

const _names = {
  'food': 'Comida',
  'transport': 'Transporte',
  'leisure': 'Ocio',
  'health': 'Salud',
  'books': 'Libros',
  'misc': 'Varios',
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
  // Period: November 2026. Previous period (same length): Oct 2 – Oct 31.
  final start = DateTime(2026, 11, 1);
  final end = DateTime(2026, 12, 1);

  final window = [
    _tx('Mercado Central', 500, DateTime(2026, 10, 15), 'food'),
    _tx('Taxi', 100, DateTime(2026, 10, 20), 'transport'),
    _tx('Netflix', 45, DateTime(2026, 9, 5), 'leisure'),
    _tx('Supermercado Éxito', 300, DateTime(2026, 11, 3), 'food'),
    _tx('Restaurante Pizza', 200, DateTime(2026, 11, 10), 'food'),
    _tx('Bus', 100, DateTime(2026, 11, 5), 'transport'),
    _tx('Gimnasio', 50, DateTime(2026, 11, 7), 'health'),
    _tx('Cine', 40, DateTime(2026, 11, 20), 'leisure'),
    _tx('Libros', 10, DateTime(2026, 11, 25), 'books'),
    _tx('Chicle', 5, DateTime(2026, 11, 26), 'misc'),
    _tx('Netflix', 45, DateTime(2026, 11, 5), 'leisure'),
    _tx('Café Bonito', 3, DateTime(2026, 11, 9), 'food'),
    _tx('café bonito ', 3, DateTime(2026, 11, 19), 'food'),
  ];

  test('sums the period and ranks the top categories', () {
    final result = computeInsightsAggregates(
      start: start,
      end: end,
      transactions: window,
    );

    expect(result.total, 756.0);
    expect(result.topCategories.map((c) => c.categoryId), [
      'food',
      'transport',
      'leisure',
      'health',
      'books',
    ]);
    expect(result.topCategories.first.amount, 506.0);
    expect(result.topCategories.first.share, closeTo(506 / 756, 1e-9));
  });

  test('limits the top categories with topCount', () {
    final result = computeInsightsAggregates(
      start: start,
      end: end,
      transactions: window,
      topCount: 2,
    );

    expect(result.topCategories.map((c) => c.categoryId), [
      'food',
      'transport',
    ]);
  });

  test('compares the total with the previous period of the same length', () {
    final result = computeInsightsAggregates(
      start: start,
      end: end,
      transactions: window,
    );

    expect(result.previousTotal, 600.0);
    expect(result.variationPercent, closeTo(26, 1e-9));
  });

  test('has no variation when the previous period had no spending', () {
    final result = computeInsightsAggregates(
      start: start,
      end: end,
      transactions: window.where((t) => t.date.month == 11).toList(),
    );

    expect(result.previousTotal, 0.0);
    expect(result.variationPercent, isNull);
  });

  test('uses start-inclusive and end-exclusive boundaries', () {
    final result = computeInsightsAggregates(
      start: start,
      end: end,
      transactions: [
        _tx('Antes', 9000, DateTime(2026, 10, 1), 'food'),
        _tx('Previo', 600, DateTime(2026, 10, 2), 'food'),
        _tx('Inicio', 100, DateTime(2026, 11, 1), 'food'),
        _tx('Despues', 7777, DateTime(2026, 12, 1), 'food'),
      ],
    );

    expect(result.total, 100.0);
    expect(result.previousTotal, 600.0);
    expect(result.variationPercent, closeTo(-83.33, 0.01));
  });

  test('lists only titles that appear in at least two months', () {
    final result = computeInsightsAggregates(
      start: start,
      end: end,
      transactions: window,
    );

    expect(result.recurring.map((r) => r.title), ['Netflix']);
    expect(result.recurring.single.months, 2);
    expect(result.recurring.single.amount, 45.0);
  });

  test(
    'flags no anomaly when no expense exceeds twice its category average',
    () {
      final result = computeInsightsAggregates(
        start: start,
        end: end,
        transactions: window,
      );

      expect(result.anomalies, isEmpty);
    },
  );

  test('flags an expense above twice its category average', () {
    final result = computeInsightsAggregates(
      start: start,
      end: end,
      transactions: [
        _tx('Mercado A', 100, DateTime(2026, 10, 10), 'food'),
        _tx('Mercado B', 120, DateTime(2026, 10, 20), 'food'),
        _tx('Mercado C', 110, DateTime(2026, 11, 3), 'food'),
        _tx('Banquete', 500, DateTime(2026, 11, 15), 'food'),
      ],
    );

    expect(result.anomalies.map((a) => a.title), ['Banquete']);
    expect(result.anomalies.single.categoryAverage, 207.5);
    expect(result.anomalies.single.categoryName, 'Comida');
  });

  test('returns empty aggregates when there are no transactions', () {
    final result = computeInsightsAggregates(
      start: start,
      end: end,
      transactions: const [],
    );

    expect(result.total, 0.0);
    expect(result.variationPercent, isNull);
    expect(result.topCategories, isEmpty);
    expect(result.recurring, isEmpty);
    expect(result.anomalies, isEmpty);
  });
}
