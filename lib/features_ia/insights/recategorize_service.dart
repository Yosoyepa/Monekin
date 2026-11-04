// AI category proposals for existing transactions (T002). Nothing is written until the caller applies accepted proposals.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/privacy/statement_redaction.dart';

const recategorizeBatchSize = 50;

/// Changes only the category of each accepted proposal that has one. Returns the number of rows updated.
Future<int> applyRecategorization(
  TransactionService transactions,
  List<RecategorizeProposal> accepted,
) async {
  var updated = 0;
  for (final proposal in accepted) {
    final categoryId = proposal.categoryId;
    if (categoryId == null) continue;

    final transaction = await transactions
        .getTransactionById(proposal.transactionId)
        .first;
    if (transaction == null) continue;

    updated += await transactions.updateTransaction(
      transaction.copyWith(categoryID: Value(categoryId)),
    );
  }
  return updated;
}

class RecategorizeItem {
  const RecategorizeItem({
    required this.id,
    required this.title,
    required this.amount,
    this.isIncome = false,
  });

  final String id;
  final String title;

  /// Shown to the user; never sent to the AI.
  final double amount;
  final bool isIncome;
}

class RecategorizeProposal {
  const RecategorizeProposal({
    required this.transactionId,
    required this.title,
    required this.amount,
    required this.categoryId,
  });

  final String transactionId;
  final String title;
  final double amount;

  /// Id from the catalog, or null when the AI gave none or an id the catalog does not have.
  final String? categoryId;
}

class RecategorizeService {
  const RecategorizeService({
    required this.client,
    required this.catalog,
    required this.transactions,
  });

  final AiClient client;
  final AiCatalog catalog;
  final TransactionService transactions;

  /// One category proposal per item, asked in batches of [recategorizeBatchSize]. Only the categories and, per
  /// transaction, its title (identifiers masked) and sign are sent: no accounts, notes or amounts. A category that does
  /// not fit the type of the transaction is discarded: the proposal then has no category.
  Future<List<RecategorizeProposal>> propose(
    List<RecategorizeItem> items,
  ) async {
    final categoryTypes = {for (final c in catalog.categories) c.id: c.type};
    final proposals = <RecategorizeProposal>[];

    for (var start = 0; start < items.length; start += recategorizeBatchSize) {
      final batch = items.skip(start).take(recategorizeBatchSize).toList();
      final answers = _answers(
        await client.chatWithCap(
          _messages(batch),
          maxTokens: AiTokenCaps.recategorize,
        ),
      );

      for (var i = 0; i < batch.length; i++) {
        final item = batch[i];
        final categoryId = answers[i];
        proposals.add(
          RecategorizeProposal(
            transactionId: item.id,
            title: item.title,
            amount: item.amount,
            categoryId: _fits(item, categoryTypes[categoryId])
                ? categoryId
                : null,
          ),
        );
      }
    }
    return proposals;
  }

  /// An expense takes an expense (E) or both (B) category, an income an income (I) or both one; any other id is dropped.
  bool _fits(RecategorizeItem item, String? categoryType) =>
      categoryType == 'B' || categoryType == (item.isIncome ? 'I' : 'E');

  Future<int> apply(List<RecategorizeProposal> accepted) =>
      applyRecategorization(transactions, accepted);

  List<AiMessage> _messages(List<RecategorizeItem> batch) {
    final rows = [
      for (var i = 0; i < batch.length; i++)
        {
          'n': i,
          'title': maskStatementIdentifiers(batch[i].title),
          'sign': batch[i].isIncome ? '+' : '-',
        },
    ];
    return [
      const AiMessage.system(
        'Classify each transaction into one category of the catalog, using only its ids, or null when none fits. '
        'The sign "-" is an expense and "+" is an income. '
        'Answer only with a JSON object: {"items": [{"n": 0, "categoryId": "..."}]}, one entry per transaction.',
      ),
      AiMessage.user(
        'Catalog: ${catalog.categoriesForPrompt()}\nTransactions: ${jsonEncode(rows)}',
      ),
    ];
  }

  Map<int, String?> _answers(AiResult result) {
    final items = result.json()['items'];
    if (items is! List) return {};

    return {
      for (final item in items.whereType<Map<String, dynamic>>())
        if (item['n'] is int)
          item['n'] as int: item['categoryId'] is String
              ? item['categoryId'] as String
              : null,
    };
  }
}
