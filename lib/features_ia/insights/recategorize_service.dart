// AI category proposals for existing transactions (T002). Nothing is written until the caller applies accepted proposals.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';

const recategorizeBatchSize = 50;

class RecategorizeItem {
  const RecategorizeItem({
    required this.id,
    required this.title,
    required this.amount,
  });

  final String id;
  final String title;
  final double amount;
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

  /// One category proposal per item, asked in batches of [recategorizeBatchSize]. Only titles and amounts are sent.
  Future<List<RecategorizeProposal>> propose(
    List<RecategorizeItem> items,
  ) async {
    final categoryIds = {for (final c in catalog.categories) c.id};
    final proposals = <RecategorizeProposal>[];

    for (var start = 0; start < items.length; start += recategorizeBatchSize) {
      final batch = items.skip(start).take(recategorizeBatchSize).toList();
      final answers = _answers(await client.chat(_messages(batch)));

      for (var i = 0; i < batch.length; i++) {
        final item = batch[i];
        final categoryId = answers[i];
        proposals.add(
          RecategorizeProposal(
            transactionId: item.id,
            title: item.title,
            amount: item.amount,
            categoryId: categoryId != null && categoryIds.contains(categoryId)
                ? categoryId
                : null,
          ),
        );
      }
    }
    return proposals;
  }

  /// Changes only the category of each accepted proposal that has one. Returns the number of rows updated.
  Future<int> apply(List<RecategorizeProposal> accepted) async {
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

  List<AiMessage> _messages(List<RecategorizeItem> batch) {
    final rows = [
      for (var i = 0; i < batch.length; i++)
        {'n': i, 'title': batch[i].title, 'amount': batch[i].amount},
    ];
    return [
      const AiMessage.system(
        'Classify each transaction into one category of the catalog, using only its ids, or null when none fits. '
        'Answer only with a JSON object: {"items": [{"n": 0, "categoryId": "..."}]}, one entry per transaction.',
      ),
      AiMessage.user(
        'Catalog: ${catalog.toPromptJson()}\nTransactions: ${jsonEncode(rows)}',
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
