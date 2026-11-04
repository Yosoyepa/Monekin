// Local aggregates behind the insights page and the weekly summary (T002). Pure Dart.

const _anomalyFactor = 2;

/// An expense in the main currency. [amount] is positive.
class InsightTransaction {
  const InsightTransaction({
    required this.title,
    required this.amount,
    required this.date,
    required this.categoryId,
    required this.categoryName,
  });

  final String title;
  final double amount;
  final DateTime date;
  final String categoryId;
  final String categoryName;
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.amount,
    required this.share,
  });

  final String categoryId;
  final String name;
  final double amount;

  /// Fraction of the period total, from 0 to 1.
  final double share;
}

class RecurringExpense {
  const RecurringExpense({
    required this.title,
    required this.months,
    required this.amount,
  });

  final String title;

  /// Distinct months in which the title appears in the analysed window.
  final int months;

  /// Amount spent with this title inside the period.
  final double amount;
}

class AnomalyExpense {
  const AnomalyExpense({
    required this.title,
    required this.categoryName,
    required this.amount,
    required this.categoryAverage,
  });

  final String title;
  final String categoryName;
  final double amount;
  final double categoryAverage;
}

class InsightsAggregates {
  const InsightsAggregates({
    required this.start,
    required this.end,
    required this.total,
    required this.previousTotal,
    required this.topCategories,
    required this.recurring,
    required this.anomalies,
  });

  final DateTime start;
  final DateTime end;
  final double total;
  final double previousTotal;
  final List<CategoryTotal> topCategories;
  final List<RecurringExpense> recurring;
  final List<AnomalyExpense> anomalies;

  /// Change against the previous period of the same length, or null when that period had no spending.
  double? get variationPercent =>
      previousTotal <= 0 ? null : (total - previousTotal) / previousTotal * 100;
}

/// Aggregates the expenses in [start, end) and compares them with the period right before it, of the same length.
/// [transactions] is the analysis window and must cover the previous period too: recurring titles and
/// category averages are taken from it.
InsightsAggregates computeInsightsAggregates({
  required DateTime start,
  required DateTime end,
  required List<InsightTransaction> transactions,
  int topCount = 5,
}) {
  final previousStart = start.subtract(end.difference(start));
  final current = transactions
      .where((t) => !t.date.isBefore(start) && t.date.isBefore(end))
      .toList();
  final previous = transactions
      .where((t) => !t.date.isBefore(previousStart) && t.date.isBefore(start))
      .toList();
  final total = _sum(current);

  final amountByCategory = <String, double>{};
  final nameByCategory = <String, String>{};
  for (final t in current) {
    amountByCategory.update(
      t.categoryId,
      (sum) => sum + t.amount,
      ifAbsent: () => t.amount,
    );
    nameByCategory[t.categoryId] = t.categoryName;
  }
  final sortedCategories = amountByCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topCategories = [
    for (final entry in sortedCategories.take(topCount))
      CategoryTotal(
        categoryId: entry.key,
        name: nameByCategory[entry.key]!,
        amount: entry.value,
        share: total == 0 ? 0.0 : entry.value / total,
      ),
  ];

  final monthsByTitle = <String, Set<int>>{};
  for (final t in transactions) {
    monthsByTitle
        .putIfAbsent(_titleKey(t.title), () => <int>{})
        .add(t.date.year * 12 + t.date.month);
  }
  final recurringAmount = <String, double>{};
  final recurringTitle = <String, String>{};
  for (final t in current) {
    final key = _titleKey(t.title);
    if ((monthsByTitle[key]?.length ?? 0) < 2) continue;
    recurringAmount.update(
      key,
      (sum) => sum + t.amount,
      ifAbsent: () => t.amount,
    );
    recurringTitle.putIfAbsent(key, () => t.title);
  }
  final recurring = [
    for (final key in recurringAmount.keys)
      RecurringExpense(
        title: recurringTitle[key]!,
        months: monthsByTitle[key]!.length,
        amount: recurringAmount[key]!,
      ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));

  final totalByCategory = <String, double>{};
  final countByCategory = <String, int>{};
  for (final t in transactions) {
    totalByCategory.update(
      t.categoryId,
      (sum) => sum + t.amount,
      ifAbsent: () => t.amount,
    );
    countByCategory.update(
      t.categoryId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final anomalies = <AnomalyExpense>[];
  for (final t in current) {
    final average =
        totalByCategory[t.categoryId]! / countByCategory[t.categoryId]!;
    if (average > 0 && t.amount > _anomalyFactor * average) {
      anomalies.add(
        AnomalyExpense(
          title: t.title,
          categoryName: t.categoryName,
          amount: t.amount,
          categoryAverage: average,
        ),
      );
    }
  }
  anomalies.sort((a, b) => b.amount.compareTo(a.amount));

  return InsightsAggregates(
    start: start,
    end: end,
    total: total,
    previousTotal: _sum(previous),
    topCategories: topCategories,
    recurring: recurring,
    anomalies: anomalies,
  );
}

double _sum(Iterable<InsightTransaction> transactions) =>
    transactions.fold(0.0, (sum, t) => sum + t.amount);

String _titleKey(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
