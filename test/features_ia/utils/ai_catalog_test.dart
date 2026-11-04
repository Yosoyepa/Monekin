import 'dart:convert';

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
  const catalog = AiCatalog(
    accounts: [
      CatalogAccount(id: 'acc-1', name: 'Bancolombia', currency: 'COP'),
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
      CatalogCategory(id: 'cat-4', name: 'Transferencias', type: 'B'),
    ],
  );

  group('categoriesForPrompt', () {
    test('writes the compact shape: id, name, parent and type', () {
      expect(
        catalog.categoriesForPrompt(),
        '{"categories":[{"id":"cat-1","name":"Alimentación","type":"E"},{"id":"cat-2","name":"Restaurantes","parent":"Alimentación","type":"E"},{"id":"cat-3","name":"Salario","type":"I"},{"id":"cat-4","name":"Transferencias","type":"B"}]}',
      );
    });

    test('never carries accounts', () {
      final json = catalog.categoriesForPrompt();

      expect(json, isNot(contains('acc-1')));
      expect(json, isNot(contains('Bancolombia')));
      expect(json, isNot(contains('Efectivo')));
      expect(json, isNot(contains('accounts')));
    });

    test('can keep only some types', () {
      final json = jsonDecode(catalog.categoriesForPrompt(types: {'E'})) as Map;

      expect((json['categories'] as List).map((c) => (c as Map)['id']), [
        'cat-1',
        'cat-2',
      ]);
    });
  });

  group('loadAiCatalog', () {
    tearDown(() => debugCatalogSource = null);

    test(
      'maps the open accounts and every category, without a database',
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
        );

        final loaded = await loadAiCatalog();

        expect(loaded.accounts.map((a) => a.id), ['acc-1', 'acc-3']);
        expect(loaded.accounts.map((a) => a.name), ['Bancolombia', 'Nequi']);
        expect(
          loaded.categoriesForPrompt(),
          '{"categories":[{"id":"cat-1","name":"Alimentación","type":"E"},{"id":"cat-2","name":"Restaurantes","parent":"Alimentación","type":"E"},{"id":"cat-3","name":"Salario","type":"I"},{"id":"cat-4","name":"Transferencias","type":"B"}]}',
        );
      },
    );
  });
}
