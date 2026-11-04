// What the recategorization page reads and writes (T002). Production uses Monekin; tests inject fakes.
import 'package:flutter/material.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/insights/insights_period.dart';
import 'package:monekin/features_ia/insights/recategorize_service.dart';

class RecategorizeFilter {
  const RecategorizeFilter({
    required this.period,
    this.customRange,
    this.categoryId,
    this.text = '',
  });

  final InsightsPeriod period;
  final DateTimeRange? customRange;
  final String? categoryId;
  final String text;
}

class RecategorizeGateway {
  const RecategorizeGateway({
    required this.loadItems,
    required this.loadCatalog,
    required this.propose,
    required this.apply,
  });

  final Future<List<RecategorizeItem>> Function(RecategorizeFilter filter)
  loadItems;
  final Future<AiCatalog> Function() loadCatalog;

  /// Throws [AiException] with [AiErrorKind.notConfigured] when no AI provider is set up.
  final Future<List<RecategorizeProposal>> Function(
    List<RecategorizeItem> items,
  )
  propose;

  /// Writes the accepted proposals and returns how many transactions changed.
  final Future<int> Function(List<RecategorizeProposal> accepted) apply;

  static const monekin = RecategorizeGateway(
    loadItems: loadRecategorizeItemsFromMonekin,
    loadCatalog: loadAiCatalog,
    propose: _proposeWithAi,
    apply: _applyInMonekin,
  );
}

/// Expenses and income in the filter's period, category and title text.
Future<List<RecategorizeItem>> loadRecategorizeItemsFromMonekin(
  RecategorizeFilter filter,
) async {
  final range = insightsRangeOf(filter.period, custom: filter.customRange);
  final text = filter.text.trim();
  final categoryId = filter.categoryId;
  final rows = await TransactionService.instance
      .getTransactions(
        filters: TransactionFilterSet(
          minDate: range.start,
          maxDate: range.end,
          categoriesIds: categoryId == null ? null : [categoryId],
          searchValue: text.isEmpty ? null : text,
          transactionTypes: const [
            TransactionType.expense,
            TransactionType.income,
          ],
        ),
      )
      .first;

  return [
    for (final tx in rows)
      RecategorizeItem(
        id: tx.id,
        title: tx.title ?? '',
        amount: tx.currentValueInPreferredCurrency.abs(),
      ),
  ];
}

Future<List<RecategorizeProposal>> _proposeWithAi(
  List<RecategorizeItem> items,
) async {
  final client = await AiService.instance.client();
  final catalog = await loadAiCatalog();
  return RecategorizeService(
    client: client,
    catalog: catalog,
    transactions: TransactionService.instance,
  ).propose(items);
}

Future<int> _applyInMonekin(List<RecategorizeProposal> accepted) =>
    applyRecategorization(TransactionService.instance, accepted);
