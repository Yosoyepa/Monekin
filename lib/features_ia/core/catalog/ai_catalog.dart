// Accounts and categories sent to the AI so it only proposes ids that exist (T002). Owner: w-utils.
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:monekin/core/database/services/account/account_service.dart';
import 'package:monekin/core/database/services/category/category_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/features_ia/core/cards/card_map.dart';

class CatalogAccount {
  const CatalogAccount({
    required this.id,
    required this.name,
    required this.currency,
    this.cardLast4 = const [],
  });

  final String id;
  final String name;

  /// ISO code, e.g. `COP`.
  final String currency;

  /// Last four digits of the cards mapped to this account (card map).
  final List<String> cardLast4;
}

class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    required this.type,
    this.parentName,
  });

  final String id;

  /// Subcategory name, or the category name when it has no parent.
  final String name;

  /// `E` expense, `I` income, `B` both (from the parent for subcategories).
  final String type;
  final String? parentName;
}

class AiCatalog {
  const AiCatalog({required this.accounts, required this.categories});

  final List<CatalogAccount> accounts;
  final List<CatalogCategory> categories;

  /// Compact JSON for prompts: `{"accounts":[...],"categories":[...]}`. Accounts carry id, name, currency and
  /// `last4` when they have cards; categories carry id, name, `parent` when they have one, and type.
  String toPromptJson() => jsonEncode({
    'accounts': [
      for (final account in accounts)
        {
          'id': account.id,
          'name': account.name,
          'currency': account.currency,
          if (account.cardLast4.isNotEmpty) 'last4': account.cardLast4,
        },
    ],
    'categories': [
      for (final category in categories)
        {
          'id': category.id,
          'name': category.name,
          if (category.parentName != null) 'parent': category.parentName,
          'type': category.type,
        },
    ],
  });
}

typedef CatalogSource = ({
  List<Account> accounts,
  List<Category> categories,
  Map<String, String> cardMap,
});

/// Test seam: replaces the Monekin and card map reads of [loadAiCatalog].
@visibleForTesting
Future<CatalogSource> Function()? debugCatalogSource;

/// Reads the user's accounts and categories from Monekin (and the card map).
Future<AiCatalog> loadAiCatalog() async {
  final source = await (debugCatalogSource?.call() ?? _readMonekin());

  return AiCatalog(
    accounts: [
      for (final account in source.accounts)
        if (!account.isClosed)
          CatalogAccount(
            id: account.id,
            name: account.name,
            currency: account.currency.code,
            cardLast4: [
              for (final entry in source.cardMap.entries)
                if (entry.value == account.id) entry.key,
            ],
          ),
    ],
    categories: [
      for (final category in source.categories)
        CatalogCategory(
          id: category.id,
          name: category.name,
          type: category.type.name,
          parentName: category.parentCategory?.name,
        ),
    ],
  );
}

Future<CatalogSource> _readMonekin() async => (
  accounts: await AccountService.instance.getAccounts().first,
  categories: await CategoryService.instance.getCategories().first,
  cardMap: await CardMapService.instance.load(),
);
