import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/currency/currency.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';

Account account(String id, String name, {DateTime? closed}) => Account(
  id: id,
  name: name,
  iniValue: 0,
  date: DateTime(2026),
  type: AccountType.money,
  displayOrder: 0,
  iconId: 'bank',
  currency: Currency(name: 'Peso colombiano', code: 'COP', symbol: r'$'),
  closingDate: closed,
);

Category category(
  String id,
  String name,
  CategoryType type, {
  Category? parent,
}) => Category(
  id: id,
  name: name,
  iconId: 'food',
  displayOrder: 0,
  color: parent == null ? '737373' : null,
  type: parent == null ? type : null,
  parentCategory: parent,
);

void main() {
  test(
    'toPromptJson writes the compact shape: id, name, currency, last4, parent and type',
    () {
      const catalog = AiCatalog(
        accounts: [
          CatalogAccount(
            id: 'acc-1',
            name: 'Bancolombia',
            currency: 'COP',
            cardLast4: ['1234'],
          ),
          CatalogAccount(id: 'acc-2', name: 'Efectivo', currency: 'COP'),
        ],
        categories: [
          CatalogCategory(id: 'cat-1', name: 'Alimentación', type: 'E'),
          CatalogCategory(
            id: 'cat-2',
            name: 'Restaurantes',
            type: 'E',
            parentName: 'Alimentación',
          ),
          CatalogCategory(id: 'cat-3', name: 'Salario', type: 'I'),
        ],
      );

      expect(
        catalog.toPromptJson(),
        '{"accounts":[{"id":"acc-1","name":"Bancolombia","currency":"COP","last4":["1234"]},{"id":"acc-2","name":"Efectivo","currency":"COP"}],"categories":[{"id":"cat-1","name":"Alimentación","type":"E"},{"id":"cat-2","name":"Restaurantes","parent":"Alimentación","type":"E"},{"id":"cat-3","name":"Salario","type":"I"}]}',
      );
    },
  );

  group('loadAiCatalog', () {
    tearDown(() => debugCatalogSource = null);

    test(
      'maps the open accounts with their cards and every category, without a database',
      () async {
        final food = category('cat-1', 'Alimentación', CategoryType.E);

        debugCatalogSource = () async => (
          accounts: [
            account('acc-1', 'Bancolombia'),
            account('acc-2', 'Efectivo', closed: DateTime(2026, 5)),
            account('acc-3', 'Nequi'),
          ],
          categories: [
            food,
            category('cat-2', 'Restaurantes', CategoryType.E, parent: food),
            category('cat-3', 'Salario', CategoryType.I),
            category('cat-4', 'Transferencias', CategoryType.B),
          ],
          cardMap: {'1234': 'acc-1', '9999': 'acc-gone'},
        );

        final catalog = await loadAiCatalog();

        expect(
          catalog.toPromptJson(),
          '{"accounts":[{"id":"acc-1","name":"Bancolombia","currency":"COP","last4":["1234"]},{"id":"acc-3","name":"Nequi","currency":"COP"}],"categories":[{"id":"cat-1","name":"Alimentación","type":"E"},{"id":"cat-2","name":"Restaurantes","parent":"Alimentación","type":"E"},{"id":"cat-3","name":"Salario","type":"I"},{"id":"cat-4","name":"Transferencias","type":"B"}]}',
        );
      },
    );
  });
}
