// Recommendation prompt built only from aggregates (T002): individual transactions never leave the device.
import 'dart:convert';

import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';

List<AiMessage> buildRecommendationMessages(
  InsightsAggregates aggregates, {
  required String currency,
  required String language,
  int tipCount = 3,
}) {
  final payload = {
    'currency': currency,
    'period': {'start': _day(aggregates.start), 'end': _day(aggregates.end)},
    'totalExpenses': _round(aggregates.total),
    'previousPeriodExpenses': _round(aggregates.previousTotal),
    'variationPercent': _round(aggregates.variationPercent),
    'topCategories': [
      for (final c in aggregates.topCategories)
        {
          'name': c.name,
          'amount': _round(c.amount),
          'sharePercent': _round(c.share * 100),
        },
    ],
    'recurring': {
      'count': aggregates.recurring.length,
      'total': _round(
        aggregates.recurring.fold<double>(0, (sum, r) => sum + r.amount),
      ),
    },
    'anomalies': {
      'count': aggregates.anomalies.length,
      'categories': {
        for (final a in aggregates.anomalies) a.categoryName,
      }.toList(),
    },
  };
  final noun = tipCount == 1 ? 'tip' : 'tips';
  return [
    AiMessage.system(
      'You are a personal finance assistant. The user message holds aggregated figures of one period. '
      'Give exactly $tipCount short, concrete $noun based only on those figures, written in $language. '
      'Answer only with a JSON object: {"tips": [...]} with $tipCount strings.',
    ),
    AiMessage.user(jsonEncode(payload)),
  ];
}

String _day(DateTime date) => date.toIso8601String().substring(0, 10);

double? _round(double? value) =>
    value == null ? null : double.parse(value.toStringAsFixed(2));
