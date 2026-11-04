// Weekly summary (T002): the last seven days, calculated on the phone. It never calls the AI: it runs in the
// background, where nobody could see or cancel what was sent. The recommendations from the AI are asked for on the
// insights screen, with their own consent and «See what is sent».
import 'package:intl/intl.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class InsightsServiceImpl implements InsightsService {
  InsightsServiceImpl({
    required this.loadExpenses,
    required this.preferredCurrency,
    this.now = DateTime.now,
  });

  /// Expenses dated in [start, end), in the preferred currency.
  final Future<List<InsightTransaction>> Function(DateTime start, DateTime end)
  loadExpenses;
  final Future<CurrencyInDB> Function() preferredCurrency;
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

    return WeeklySummary(
      title: t.ia_insights.weekly.title,
      body: t.ia_insights.weekly.body(total: total, tip: _localTips(week)),
    );
  }

  /// The comparison with the week before, the busiest category and the biggest unusual expense, by fixed rules.
  String _localTips(InsightsAggregates week) {
    final variation = week.variationPercent;
    final top = week.topCategories.first;
    return [
      if (variation != null && variation.round() != 0)
        variation > 0
            ? t.ia_insights.weekly.up(percent: '${variation.round()}')
            : t.ia_insights.weekly.down(percent: '${variation.abs().round()}'),
      t.ia_insights.weekly.tip(
        category: top.name,
        share: (top.share * 100).round().toString(),
      ),
      if (week.anomalies.isNotEmpty)
        t.ia_insights.weekly.tip_anomaly(
          title: week.anomalies.first.title,
          category: week.anomalies.first.categoryName,
        ),
    ].join(' ');
  }
}
