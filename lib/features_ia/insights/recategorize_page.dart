// Recategorization page (T002): the AI proposes a category per transaction, and only accepted proposals are written.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/consent/ai_consent_sheet.dart';
import 'package:monekin/features_ia/insights/insights_period.dart';
import 'package:monekin/features_ia/insights/recategorize_gateway.dart';
import 'package:monekin/features_ia/insights/recategorize_service.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class _Pick {
  /// Proposals start unchecked: only what the user marks is applied.
  _Pick(this.proposal) : accepted = false;

  final RecategorizeProposal proposal;
  bool accepted;
}

class RecategorizePage extends StatefulWidget {
  const RecategorizePage({super.key, this.gateway});

  /// Tests inject fakes here. The app uses [RecategorizeGateway.monekin].
  final RecategorizeGateway? gateway;

  @override
  State<RecategorizePage> createState() => _RecategorizePageState();
}

class _RecategorizePageState extends State<RecategorizePage> {
  final _searchController = TextEditingController();
  InsightsPeriod _period = InsightsPeriod.current;
  DateTimeRange? _customRange;
  String? _categoryId;
  AiCatalog? _catalog;
  List<RecategorizeItem> _items = const [];
  List<_Pick> _picks = const [];
  Map<String, String> _previous = const {};
  bool _busy = false;
  bool _proposing = false;
  String? _message;
  IaTone _messageTone = IaTone.error;

  RecategorizeGateway get _gateway =>
      widget.gateway ?? RecategorizeGateway.monekin;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final catalog = await _gateway.loadCatalog();
      if (mounted) setState(() => _catalog = catalog);
    } on Exception {
      if (mounted) {
        setState(() {
          _message = t.ia_insights.load_failed;
          _messageTone = IaTone.error;
        });
      }
      return;
    }
    await _reload();
  }

  Future<void> _reload({String? message}) async {
    setState(() => _busy = true);
    try {
      final items = await _gateway.loadItems(
        RecategorizeFilter(
          period: _period,
          customRange: _customRange,
          categoryId: _categoryId,
          text: _searchController.text,
        ),
      );
      if (mounted) {
        setState(() {
          _items = items;
          _picks = const [];
          _message = message;
          _messageTone = IaTone.success;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _message = t.ia_insights.load_failed;
          _messageTone = IaTone.error;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectPeriod(InsightsPeriod period) async {
    if (period == InsightsPeriod.custom) {
      final picked = await pickInsightsRange(context, _customRange);
      if (picked == null || !mounted) return;
      _customRange = picked;
    }
    setState(() => _period = period);
    await _reload();
  }

  Future<void> _selectCategory(String? categoryId) async {
    setState(() => _categoryId = categoryId);
    await _reload();
  }

  Future<void> _showSent() async {
    final describe = _gateway.describeSent;
    if (describe == null) return;
    final text = await describe(_items);
    if (mounted) await showAiSentDialog(context, text: text);
  }

  Future<void> _propose() async {
    final ensure = _gateway.ensureConsent;
    if (ensure != null && !await ensure(context)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _proposing = true;
      _message = null;
    });
    try {
      final proposals = await _gateway.propose(_items);
      final previous = await _previousOf(proposals);
      if (mounted) {
        setState(() {
          _picks = [for (final p in proposals) _Pick(p)];
          _previous = previous;
        });
      }
    } on AiException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.kind == AiErrorKind.notConfigured
              ? t.ia_insights.not_configured
              : t.ia_insights.ai_failed;
          _messageTone = error.kind == AiErrorKind.notConfigured
              ? IaTone.info
              : IaTone.error;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _message = t.ia_insights.ai_failed;
          _messageTone = IaTone.error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _proposing = false;
        });
      }
    }
  }

  /// A failed lookup only hides the «before» half of the line.
  Future<Map<String, String>> _previousOf(
    List<RecategorizeProposal> proposals,
  ) async {
    final load = _gateway.loadPreviousCategories;
    if (load == null) return const {};

    try {
      return await load([for (final p in proposals) p.transactionId]);
    } on Exception {
      return const {};
    }
  }

  void _selectAll() => setState(() {
    for (final pick in _picks) {
      if (pick.proposal.categoryId != null) pick.accepted = true;
    }
  });

  Future<void> _apply() async {
    final accepted = [
      for (final pick in _picks)
        if (pick.accepted && pick.proposal.categoryId != null) pick.proposal,
    ];
    setState(() => _busy = true);
    try {
      final updated = await _gateway.apply(accepted);
      await _reload(
        message: t.ia_insights.recategorize.applied(count: '$updated'),
      );
    } on Exception {
      if (mounted) {
        setState(() {
          _message = t.ia_insights.recategorize.apply_failed;
          _messageTone = IaTone.error;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _categoryName(String categoryId) {
    for (final category in _catalog?.categories ?? const <CatalogCategory>[]) {
      if (category.id == categoryId) return category.name;
    }
    return categoryId;
  }

  String _proposalLine(RecategorizeProposal proposal) {
    final categoryId = proposal.categoryId;
    if (categoryId == null) return t.ia_insights.recategorize.no_proposal;

    final previous = _previous[proposal.transactionId];
    final next = _categoryName(categoryId);
    return previous == null
        ? t.ia_insights.recategorize.proposed_to(category: next)
        : t.ia_insights.recategorize.changed_to(
            previous: previous,
            category: next,
          );
  }

  String _amount(double value) => NumberFormat.decimalPattern().format(value);

  @override
  Widget build(BuildContext context) {
    final categories = _catalog?.categories ?? const <CatalogCategory>[];
    final hasAccepted = _picks.any(
      (pick) => pick.accepted && pick.proposal.categoryId != null,
    );

    return PageFramework(
      title: t.ia_insights.recategorize.title,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          BrandTokens.pageMargin,
          8,
          BrandTokens.pageMargin,
          32,
        ),
        children: [
          InsightsPeriodTabs(selected: _period, onSelected: _selectPeriod),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(t.ia_insights.recategorize.all_categories),
                selected: _categoryId == null,
                onSelected: (_) => _selectCategory(null),
              ),
              for (final category in categories)
                ChoiceChip(
                  label: Text(category.name),
                  selected: _categoryId == category.id,
                  onSelected: (_) => _selectCategory(category.id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(
              labelText: t.ia_insights.recategorize.search,
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _busy ? null : () => _reload(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_proposing)
            IaStatusView(
              key: const Key('recategorize-thinking'),
              inline: true,
              size: 96,
              mood: ChanchiMood.thinking,
              title: t.ia_insights.recategorize.thinking,
            )
          else if (_picks.isEmpty)
            for (final item in _items)
              IaCard(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(item.title)),
                    const SizedBox(width: 12),
                    Text(
                      _amount(item.amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              )
          else
            for (final pick in _picks)
              IaCard(
                margin: const EdgeInsets.only(bottom: 8),
                padding: EdgeInsets.zero,
                child: CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  value: pick.accepted,
                  onChanged: pick.proposal.categoryId == null || _busy
                      ? null
                      : (value) =>
                            setState(() => pick.accepted = value ?? false),
                  title: Text(pick.proposal.title),
                  subtitle: Text(_proposalLine(pick.proposal)),
                  secondary: Text(
                    _amount(pick.proposal.amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
              ),
          if (_picks.isEmpty && _items.isEmpty && !_busy)
            IaStatusView(
              inline: true,
              size: 96,
              mood: ChanchiMood.sleepy,
              title: t.ia_insights.recategorize.no_items,
            ),
          if (_picks.isNotEmpty && !_proposing)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('recategorize-select-all'),
                onPressed: _busy ? null : _selectAll,
                icon: const Icon(Icons.done_all_rounded),
                label: Text(t.ia_insights.recategorize.select_all),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy || _items.isEmpty ? null : () => _propose(),
            child: Text(t.ia_insights.recategorize.propose),
          ),
          if (_gateway.describeSent != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('recategorize-see-sent'),
                onPressed: _busy || _items.isEmpty
                    ? null
                    : () => unawaited(_showSent()),
                child: Text(t.ia_consent.see_sent),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy || !hasAccepted ? null : () => _apply(),
            child: Text(t.ia_insights.recategorize.apply),
          ),
          if (_message != null)
            IaNotice(
              margin: const EdgeInsets.only(top: 12),
              tone: _messageTone,
              text: _message!,
            ),
        ],
      ),
    );
  }
}
