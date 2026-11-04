// Recategorization page (T002): the AI proposes a category per transaction, and only accepted proposals are written.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/insights/insights_period.dart';
import 'package:monekin/features_ia/insights/recategorize_gateway.dart';
import 'package:monekin/features_ia/insights/recategorize_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class _Pick {
  _Pick(this.proposal) : accepted = proposal.categoryId != null;

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
  bool _busy = false;
  String? _message;

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
      if (mounted) setState(() => _message = t.ia_insights.load_failed);
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
        });
      }
    } on Exception {
      if (mounted) setState(() => _message = t.ia_insights.load_failed);
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

  Future<void> _propose() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final proposals = await _gateway.propose(_items);
      if (mounted) {
        setState(() => _picks = [for (final p in proposals) _Pick(p)]);
      }
    } on AiException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.kind == AiErrorKind.notConfigured
              ? t.ia_insights.not_configured
              : t.ia_insights.ai_failed;
        });
      }
    } on Exception {
      if (mounted) setState(() => _message = t.ia_insights.ai_failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
        setState(() => _message = t.ia_insights.recategorize.apply_failed);
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
          if (_picks.isEmpty)
            for (final item in _items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.title),
                trailing: Text(_amount(item.amount)),
              )
          else
            for (final pick in _picks)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: pick.accepted,
                onChanged: pick.proposal.categoryId == null || _busy
                    ? null
                    : (value) => setState(() => pick.accepted = value ?? false),
                title: Text(pick.proposal.title),
                subtitle: Text(
                  pick.proposal.categoryId == null
                      ? t.ia_insights.recategorize.no_proposal
                      : t.ia_insights.recategorize.proposed_to(
                          category: _categoryName(pick.proposal.categoryId!),
                        ),
                ),
                secondary: Text(_amount(pick.proposal.amount)),
              ),
          if (_picks.isEmpty && _items.isEmpty && !_busy)
            Text(t.ia_insights.recategorize.no_items),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy || _items.isEmpty ? null : () => _propose(),
            child: Text(t.ia_insights.recategorize.propose),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy || !hasAccepted ? null : () => _apply(),
            child: Text(t.ia_insights.recategorize.apply),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!),
            ),
        ],
      ),
    );
  }
}
