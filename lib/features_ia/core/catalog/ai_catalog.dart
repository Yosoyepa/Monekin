// Accounts and categories sent to the AI so it only proposes ids that exist (T002). Owner: w-utils.
class CatalogAccount {
  const CatalogAccount({required this.id, required this.name, required this.currency, this.cardLast4 = const []});

  final String id;
  final String name;

  /// ISO code, e.g. `COP`.
  final String currency;

  /// Last four digits of the cards mapped to this account (card map).
  final List<String> cardLast4;
}

class CatalogCategory {
  const CatalogCategory({required this.id, required this.name, required this.type, this.parentName});

  final String id;

  /// Subcategory name, or the category name when it has no parent.
  final String name;

  /// `E` expense, `I` income (from the parent for subcategories).
  final String type;
  final String? parentName;
}

class AiCatalog {
  const AiCatalog({required this.accounts, required this.categories});

  final List<CatalogAccount> accounts;
  final List<CatalogCategory> categories;

  /// Compact JSON for prompts: `{"accounts":[...],"categories":[...]}` with ids, names and types only.
  String toPromptJson() => throw UnimplementedError('AiCatalog.toPromptJson is implemented by w-utils');
}

/// Reads the user's accounts and categories from Monekin (and the card map).
Future<AiCatalog> loadAiCatalog() {
  throw UnimplementedError('loadAiCatalog is implemented by w-utils');
}
