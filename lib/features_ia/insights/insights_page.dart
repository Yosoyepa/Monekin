// Insights page (T002): local figures for a period, and AI recommendations built from those figures only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_data.dart';
import 'package:monekin/features_ia/insights/insights_period.dart';
import 'package:monekin/features_ia/insights/insights_prompt.dart';
import 'package:monekin/features_ia/insights/recategorize_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class _Report {
  const _Report({required this.aggregates, required this.currency});

  final InsightsAggregates aggregates;
  final CurrencyInDB currency;
}

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  InsightsPeriod _period = InsightsPeriod.current;
  DateTimeRange? _customRange;
  late Future<_Report> _report = _load(_period);
  SavedTips? _tips;
  bool _asking = false;
  String? _aiMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedTips());
  }

  Future<void> _loadSavedTips() async {
    try {
      final saved = await InsightsData.current.loadLastTips();
      if (mounted) setState(() => _tips = saved);
    } on Exception {
      if (mounted) setState(() => _tips = null);
    }
  }

  /// Loads six months before the period too, so recurring titles and category averages have history.
  Future<_Report> _load(InsightsPeriod period) async {
    final range = insightsRangeOf(period, custom: _customRange);
    final previousStart = range.start.subtract(
      range.end.difference(range.start),
    );
    final lookbackStart = DateTime(range.start.year, range.start.month - 5);
    final from = previousStart.isBefore(lookbackStart)
        ? previousStart
        : lookbackStart;

    final data = InsightsData.current;
    final transactions = await data.loadExpenses(from, range.end);
    final currency = await data.preferredCurrency();
    return _Report(
      aggregates: computeInsightsAggregates(
        start: range.start,
        end: range.end,
        transactions: transactions,
      ),
      currency: currency,
    );
  }

  Future<void> _selectPeriod(InsightsPeriod period) async {
    if (period == InsightsPeriod.custom) {
      final picked = await pickInsightsRange(context, _customRange);
      if (picked == null || !mounted) return;
      _customRange = picked;
    }
    setState(() {
      _period = period;
      _report = _load(period);
    });
  }

  Future<void> _askForTips(
    InsightsAggregates aggregates,
    CurrencyInDB currency,
  ) async {
    setState(() {
      _asking = true;
      _aiMessage = null;
    });
    try {
      if (!await AiService.instance.isConfigured()) {
        if (mounted) setState(() => _aiMessage = t.ia_insights.not_configured);
        return;
      }

      final client = await AiService.instance.client();
      final result = await client.chat(
        buildRecommendationMessages(
          aggregates,
          currency: currency.code,
          language: insightsLanguageName(),
          tipCount: 3,
        ),
      );
      final tips = _tipsFrom(result.json());
      if (tips.isEmpty) {
        throw const AiException(
          AiErrorKind.badResponse,
          'The answer had no tips',
        );
      }

      final saved = SavedTips(savedAt: DateTime.now(), tips: tips);
      await InsightsData.current.saveLastTips(saved);
      if (mounted) setState(() => _tips = saved);
    } on Exception {
      if (mounted) setState(() => _aiMessage = t.ia_insights.ai_failed);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  List<String> _tipsFrom(Map<String, dynamic> json) {
    final tips = json['tips'];
    if (tips is! List) return const [];
    return [
      for (final tip in tips.whereType<String>())
        if (tip.trim().isNotEmpty) tip.trim(),
    ].take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: t.ia_insights.title,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          InsightsPeriodTabs(selected: _period, onSelected: _selectPeriod),
          FutureBuilder<_Report>(
            future: _report,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(t.ia_insights.load_failed);
              final report = snapshot.data;
              if (report == null) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _reportView(context, report);
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () =>
                unawaited(RouteUtils.pushRoute(const RecategorizePage())),
            icon: const Icon(Icons.category_outlined),
            label: Text(t.ia_insights.recategorize.open),
          ),
        ],
      ),
    );
  }

  Widget _reportView(BuildContext context, _Report report) {
    final aggregates = report.aggregates;
    if (aggregates.total <= 0) return Text(t.ia_insights.empty);

    final money = NumberFormat.currency(
      symbol: report.currency.symbol,
      decimalDigits: report.currency.decimalPlaces,
    );
    final variation = aggregates.variationPercent;
    final signed = NumberFormat('+#,##0.0;-#,##0.0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          money.format(aggregates.total),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          variation == null
              ? t.ia_insights.no_previous
              : t.ia_insights.vs_previous(
                  percent: '${signed.format(variation)}%',
                ),
        ),
        _section(context, t.ia_insights.top_categories, [
          for (final category in aggregates.topCategories)
            _categoryRow(category, money),
        ]),
        if (aggregates.recurring.isNotEmpty)
          _section(context, t.ia_insights.recurring, [
            for (final expense in aggregates.recurring)
              Text(
                t.ia_insights.recurring_item(
                  title: expense.title,
                  months: '${expense.months}',
                ),
              ),
          ]),
        if (aggregates.anomalies.isNotEmpty)
          _section(context, t.ia_insights.anomalies, [
            for (final expense in aggregates.anomalies)
              Text(
                t.ia_insights.anomaly_item(
                  title: expense.title,
                  category: expense.categoryName,
                  average: money.format(expense.categoryAverage),
                ),
              ),
          ]),
        _section(context, t.ia_insights.recommendations, [
          FilledButton.icon(
            onPressed: _asking
                ? null
                : () => _askForTips(aggregates, report.currency),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(t.ia_insights.get_tips),
          ),
          if (_aiMessage != null) Text(_aiMessage!),
          if (_tips != null) ...[
            const SizedBox(height: 8),
            Text(
              t.ia_insights.last_tips(
                date: DateFormat.yMMMd().format(_tips!.savedAt),
              ),
            ),
            for (final tip in _tips!.tips) Text('• $tip'),
          ],
        ]),
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  Widget _categoryRow(CategoryTotal category, NumberFormat money) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(category.name)),
            Text(money.format(category.amount)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: category.share),
      ],
    ),
  );
}
