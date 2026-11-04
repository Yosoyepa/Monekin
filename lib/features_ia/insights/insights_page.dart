// Insights page (T002): local figures for a period, and AI recommendations built from those figures only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_data.dart';
import 'package:monekin/features_ia/insights/insights_period.dart';
import 'package:monekin/features_ia/insights/insights_prompt.dart';
import 'package:monekin/features_ia/insights/recategorize_page.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
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
      final result = await client.chatWithCap(
        buildRecommendationMessages(
          aggregates,
          currency: currency.code,
          language: insightsLanguageName(),
          tipCount: 3,
        ),
        maxTokens: AiTokenCaps.insights,
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
        padding: const EdgeInsets.fromLTRB(
          BrandTokens.pageMargin,
          8,
          BrandTokens.pageMargin,
          32,
        ),
        children: [
          InsightsPeriodTabs(selected: _period, onSelected: _selectPeriod),
          FutureBuilder<_Report>(
            future: _report,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return IaStatusView(
                  inline: true,
                  mood: ChanchiMood.worried,
                  title: t.ia_insights.load_failed,
                );
              }
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
    if (aggregates.total <= 0) {
      return IaStatusView(
        inline: true,
        mood: ChanchiMood.sleepy,
        title: t.ia_insights.empty,
      );
    }

    final money = NumberFormat.currency(
      symbol: report.currency.symbol,
      decimalDigits: report.currency.decimalPlaces,
    );
    final textTheme = Theme.of(context).textTheme;
    final brand = BrandColors.of(context);
    final variation = aggregates.variationPercent;
    final signed = NumberFormat('+#,##0.0;-#,##0.0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        IaCard(
          key: const Key('insights-total'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.ia_insights.total,
                style: textTheme.labelLarge?.copyWith(
                  color: brand.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              CountUpText(
                value: aggregates.total,
                format: money.format,
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              if (variation == null)
                Text(
                  t.ia_insights.no_previous,
                  style: textTheme.bodyMedium?.copyWith(
                    color: brand.textSecondary,
                  ),
                )
              else
                IaChip(
                  label: t.ia_insights.vs_previous(
                    percent: '${signed.format(variation)}%',
                  ),
                  icon: variation > 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  // Spending more is the red one.
                  color: variation > 0 ? brand.expense : brand.income,
                ),
            ],
          ),
        ),
        _section(context, t.ia_insights.top_categories, [
          IaCard(
            child: Column(
              children: [
                for (final category in aggregates.topCategories)
                  _categoryRow(category, money),
              ],
            ),
          ),
        ]),
        if (aggregates.recurring.isNotEmpty)
          _section(context, t.ia_insights.recurring, [
            IaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final expense in aggregates.recurring)
                    _listRow(
                      Icons.event_repeat_rounded,
                      t.ia_insights.recurring_item(
                        title: expense.title,
                        months: '${expense.months}',
                      ),
                    ),
                ],
              ),
            ),
          ]),
        if (aggregates.anomalies.isNotEmpty)
          _section(context, t.ia_insights.anomalies, [
            IaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final expense in aggregates.anomalies)
                    _listRow(
                      Icons.warning_amber_rounded,
                      t.ia_insights.anomaly_item(
                        title: expense.title,
                        category: expense.categoryName,
                        average: money.format(expense.categoryAverage),
                      ),
                      color: brand.warning,
                    ),
                ],
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
          if (_asking)
            IaStatusView(
              key: const Key('insights-thinking'),
              inline: true,
              size: 96,
              mood: ChanchiMood.thinking,
              title: t.ia_insights.thinking,
            ),
          if (_aiMessage != null)
            IaNotice(
              margin: const EdgeInsets.only(top: 12),
              tone: _aiMessage == t.ia_insights.not_configured
                  ? IaTone.info
                  : IaTone.error,
              text: _aiMessage!,
            ),
          if (_tips != null && !_asking) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                t.ia_insights.last_tips(
                  date: DateFormat.yMMMd().format(_tips!.savedAt),
                ),
                style: textTheme.bodySmall?.copyWith(
                  color: brand.textSecondary,
                ),
              ),
            ),
            for (final (i, tip) in _tips!.tips.indexed)
              StaggeredEntrance(
                index: i,
                child: IaCard(
                  margin: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(tip)),
                    ],
                  ),
                ),
              ),
          ],
        ]),
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [IaSectionTitle(title), ...children],
      );

  Widget _listRow(IconData icon, String text, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: color ?? Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );

  Widget _categoryRow(CategoryTotal category, NumberFormat money) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(category.name)),
            Text(
              money.format(category.amount),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        IaBar(value: category.share),
      ],
    ),
  );
}
