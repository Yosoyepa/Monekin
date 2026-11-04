// The user's accounts and categories. Only categories ever go to the AI provider (`categoriesForPrompt`); accounts stay on the phone. Owner: w-utils.
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:monekin/core/database/services/account/account_service.dart';
import 'package:monekin/core/database/services/category/category_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/category/category.dart';

class CatalogAccount {
  const CatalogAccount({
    required this.id,
    required this.name,
    required this.currency,
  });

  final String id;
  final String name;

  /// ISO code, e.g. `COP`.
  final String currency;
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

  /// Compact JSON for prompts: `{"categories":[...]}` with id, name, `parent` when it has one, and type.
  /// [types] keeps only those types (`E`, `I`, `B`); all of them by default. Accounts are never part of it.
  String categoriesForPrompt({Set<String>? types}) => jsonEncode({
    'categories': [
      for (final category in categories)
        if (types == null || types.contains(category.type))
          {
            'id': category.id,
            'name': category.name,
            if (category.parentName != null) 'parent': category.parentName,
            'type': category.type,
          },
    ],
  });
}

typedef CatalogSource = ({List<Account> accounts, List<Category> categories});

/// Test seam: replaces the Monekin reads of [loadAiCatalog].
@visibleForTesting
Future<CatalogSource> Function()? debugCatalogSource;

/// Reads the user's accounts and categories from Monekin.
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
);
