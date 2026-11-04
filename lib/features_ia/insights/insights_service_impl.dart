// Weekly summary (T002): the last seven days with one recommendation, from the AI when it is configured.
import 'package:intl/intl.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_prompt.dart';
import 'package:monekin/features_ia/insights/insights_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class InsightsServiceImpl implements InsightsService {
  InsightsServiceImpl({
    required this.loadExpenses,
    required this.preferredCurrency,
    required this.languageName,
    this.now = DateTime.now,
  });

  /// Expenses dated in [start, end), in the preferred currency.
  final Future<List<InsightTransaction>> Function(DateTime start, DateTime end)
  loadExpenses;
  final Future<CurrencyInDB> Function() preferredCurrency;
  final String Function() languageName;
  final DateTime Function() now;

  @override
  Future<WeeklySummary?> weeklySummary() async {
    final today = now();
    final end = DateTime(today.year, today.month, today.day + 1);
    final start = end.subtract(const Duration(days: 7));
    final transactions = await loadExpenses(
      start.subtract(const Duration(days: 7)),
      end,
    );
    final week = computeInsightsAggregates(
      start: start,
      end: end,
      transactions: transactions,
      topCount: 3,
    );
    if (week.total <= 0) return null;

    final currency = await preferredCurrency();
    final total = NumberFormat.currency(
      symbol: currency.symbol,
      decimalDigits: currency.decimalPlaces,
    ).format(week.total);
    final tip = await _aiTip(week, currency.code) ?? _localTip(week);

    return WeeklySummary(
      title: t.ia_insights.weekly.title,
      body: t.ia_insights.weekly.body(total: total, tip: tip),
    );
  }

  /// The AI's recommendation, or null when there is no provider or the call fails.
  Future<String?> _aiTip(InsightsAggregates week, String currencyCode) async {
    try {
      if (!await AiService.instance.isConfigured()) return null;

      final client = await AiService.instance.client();
      final result = await client.chatWithCap(
        buildRecommendationMessages(
          week,
          currency: currencyCode,
          language: languageName(),
          tipCount: 1,
        ),
        maxTokens: AiTokenCaps.insights,
      );
      final tips = result.json()['tips'];
      if (tips is! List || tips.isEmpty) return null;

      final tip = tips.first;
      return tip is String && tip.trim().isNotEmpty ? tip.trim() : null;
    } on Exception {
      return null;
    }
  }

  String _localTip(InsightsAggregates week) {
    final top = week.topCategories.first;
    return t.ia_insights.weekly.tip(
      category: top.name,
      share: (top.share * 100).round().toString(),
    );
  }
}
