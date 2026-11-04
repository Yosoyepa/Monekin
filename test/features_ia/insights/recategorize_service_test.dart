import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/insights/recategorize_service.dart';

class _FakeCatalog extends AiCatalog {
  const _FakeCatalog()
    : super(
        accounts: const [],
        categories: const [
          CatalogCategory(id: 'cat-food', name: 'Comida', type: 'E'),
          CatalogCategory(id: 'cat-transport', name: 'Transporte', type: 'E'),
          CatalogCategory(id: 'cat-leisure', name: 'Ocio', type: 'E'),
          CatalogCategory(id: 'cat-misc', name: 'Varios', type: 'E'),
        ],
      );
}

class _FakeClient implements AiClient {
  _FakeClient(this.answer);

  final String Function(List<AiMessage> messages) answer;
  final List<List<AiMessage>> calls = [];

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls.add(messages);
    return AiResult(text: answer(messages));
  }

  @override
  Future<List<String>> listModels() async => const [];
}

void main() {
  late AppDB db;
  late TransactionService transactions;

  const items = [
    RecategorizeItem(id: 'tx-1', title: 'Mercado', amount: 80000),
    RecategorizeItem(id: 'tx-2', title: 'Uber', amount: 12000),
    RecategorizeItem(id: 'tx-3', title: 'Cine', amount: 25000),
  ];

  setUp(() async {
    db = AppDB.forTesting(NativeDatabase.memory());
    transactions = TransactionService.forTesting(db);

    await db
        .into(db.currencies)
        .insert(
          const CurrencyInDB(
            code: 'COP',
            symbol: r'$',
            name: 'Peso colombiano',
            decimalPlaces: 2,
            isDefault: true,
            type: 0,
          ),
        );

    await db
        .into(db.accounts)
        .insert(
          AccountInDB(
            id: 'acc-1',
            name: 'Cuenta',
            iniValue: 0,
            date: DateTime(2020),
            type: AccountType.money,
            isSaving: false,
            trackingMode: AccountTrackingMode.transactions,
            iconId: 'wallet',
            displayOrder: 0,
            currencyId: 'COP',
          ),
        );

    for (final category in const _FakeCatalog().categories) {
      await db
          .into(db.categories)
          .insert(
            CategoryInDB(
              id: category.id,
              name: category.name,
              iconId: 'wallet',
              color: '#4385be',
              type: CategoryType.E,
              displayOrder: 0,
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertExpense(String id) => db
      .into(db.transactions)
      .insert(
        TransactionInDB(
          id: id,
          date: DateTime(2026, 11, 3),
          accountID: 'acc-1',
          categoryID: 'cat-misc',
          value: -10,
          type: TransactionType.expense,
          isHidden: false,
        ),
      );

  Future<String?> categoryOf(String id) async =>
      (await transactions.getTransactionById(id).first)?.categoryID;

  test('applies only the two accepted proposals out of three', () async {
    for (final item in items) {
      await insertExpense(item.id);
    }
    final client = _FakeClient(
      (_) => jsonEncode({
        'items': [
          {'n': 0, 'categoryId': 'cat-food'},
          {'n': 1, 'categoryId': 'cat-transport'},
          {'n': 2, 'categoryId': 'cat-leisure'},
        ],
      }),
    );
    final service = RecategorizeService(
      client: client,
      catalog: const _FakeCatalog(),
      transactions: transactions,
    );

    final proposals = await service.propose(items);
    final updated = await service.apply([proposals[0], proposals[2]]);

    expect(proposals.map((p) => p.categoryId).toList(), [
      'cat-food',
      'cat-transport',
      'cat-leisure',
    ]);
    expect(updated, 2);
    expect(await categoryOf('tx-1'), 'cat-food');
    expect(await categoryOf('tx-2'), 'cat-misc');
    expect(await categoryOf('tx-3'), 'cat-leisure');
  });

  test(
    'keeps a null proposal for an id outside the catalog and writes nothing for it',
    () async {
      await insertExpense('tx-1');
      final client = _FakeClient(
        (_) => jsonEncode({
          'items': [
            {'n': 0, 'categoryId': 'cat-inventada'},
          ],
        }),
      );
      final service = RecategorizeService(
        client: client,
        catalog: const _FakeCatalog(),
        transactions: transactions,
      );

      final proposals = await service.propose([items.first]);
      final updated = await service.apply(proposals);

      expect(proposals.single.categoryId, isNull);
      expect(updated, 0);
      expect(await categoryOf('tx-1'), 'cat-misc');
    },
  );

  test(
    'asks in batches of at most 50, sending only title and sign per transaction',
    () async {
      final client = _FakeClient((_) => jsonEncode({'items': <Object>[]}));
      final service = RecategorizeService(
        client: client,
        catalog: const _FakeCatalog(),
        transactions: transactions,
      );
      final many = [
        for (var i = 0; i < 120; i++)
          RecategorizeItem(id: 'tx-$i', title: 'Compra $i', amount: 1000.0 + i),
      ];

      final proposals = await service.propose(many);

      expect(proposals, hasLength(120));
      expect(client.calls, hasLength(3));
      for (final call in client.calls) {
        final rows =
            jsonDecode(call.last.text.split('Transactions: ').last) as List;
        expect(rows.length, lessThanOrEqualTo(recategorizeBatchSize));
        for (final row in rows) {
          expect((row as Map).keys, unorderedEquals(['n', 'title', 'sign']));
        }
      }
    },
  );

  test(
    'a category of the other type is discarded, "both" fits either',
    () async {
      const catalog = AiCatalog(
        accounts: [],
        categories: [
          CatalogCategory(id: 'cat-food', name: 'Comida', type: 'E'),
          CatalogCategory(id: 'cat-salary', name: 'Nomina', type: 'I'),
          CatalogCategory(id: 'cat-both', name: 'Ajustes', type: 'B'),
        ],
      );
      const mixed = [
        RecategorizeItem(id: 'e-1', title: 'Mercado', amount: 1),
        RecategorizeItem(id: 'e-2', title: 'Pago', amount: 1),
        RecategorizeItem(id: 'e-3', title: 'Ajuste', amount: 1),
        RecategorizeItem(id: 'i-1', title: 'Nomina', amount: 1, isIncome: true),
        RecategorizeItem(id: 'i-2', title: 'Cobro', amount: 1, isIncome: true),
        RecategorizeItem(id: 'i-3', title: 'Ajuste', amount: 1, isIncome: true),
      ];
      final client = _FakeClient(
        (_) => jsonEncode({
          'items': [
            {'n': 0, 'categoryId': 'cat-food'},
            {'n': 1, 'categoryId': 'cat-salary'},
            {'n': 2, 'categoryId': 'cat-both'},
            {'n': 3, 'categoryId': 'cat-salary'},
            {'n': 4, 'categoryId': 'cat-food'},
            {'n': 5, 'categoryId': 'cat-both'},
          ],
        }),
      );
      final service = RecategorizeService(
        client: client,
        catalog: catalog,
        transactions: transactions,
      );

      final proposals = await service.propose(mixed);

      expect(proposals.map((p) => p.categoryId).toList(), [
        'cat-food',
        null,
        'cat-both',
        'cat-salary',
        null,
        'cat-both',
      ]);
      expect(await service.apply(proposals.sublist(1, 2)), 0);
    },
  );
}
