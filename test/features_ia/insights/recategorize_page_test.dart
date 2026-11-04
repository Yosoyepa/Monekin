import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/insights/recategorize_gateway.dart';
import 'package:monekin/features_ia/insights/recategorize_page.dart';
import 'package:monekin/features_ia/insights/recategorize_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

const _catalog = AiCatalog(
  accounts: [],
  categories: [
    CatalogCategory(id: 'cat-food', name: 'Comida', type: 'E'),
    CatalogCategory(id: 'cat-transport', name: 'Transporte', type: 'E'),
    CatalogCategory(id: 'cat-leisure', name: 'Ocio', type: 'E'),
  ],
);

const _items = [
  RecategorizeItem(id: 'tx-1', title: 'Mercado', amount: 80000),
  RecategorizeItem(id: 'tx-2', title: 'Uber', amount: 12000),
  RecategorizeItem(id: 'tx-3', title: 'Cine', amount: 25000),
];

const _proposals = [
  RecategorizeProposal(
    transactionId: 'tx-1',
    title: 'Mercado',
    amount: 80000,
    categoryId: 'cat-food',
  ),
  RecategorizeProposal(
    transactionId: 'tx-2',
    title: 'Uber',
    amount: 12000,
    categoryId: 'cat-transport',
  ),
  RecategorizeProposal(
    transactionId: 'tx-3',
    title: 'Cine',
    amount: 25000,
    categoryId: 'cat-leisure',
  ),
];

void main() {
  late List<RecategorizeProposal> applied;

  setUp(() {
    applied = [];
  });

  RecategorizeGateway fakeGateway({
    Future<List<RecategorizeProposal>> Function(List<RecategorizeItem> items)?
    propose,
  }) {
    return RecategorizeGateway(
      loadItems: (filter) async => _items,
      loadCatalog: () async => _catalog,
      propose: propose ?? (items) async => _proposals,
      apply: (accepted) async {
        applied = accepted;
        return accepted.length;
      },
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    RecategorizeGateway gateway,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: RecategorizePage(gateway: gateway)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'lists the transactions and shows a proposed category for each one',
    (tester) async {
      await pumpPage(tester, fakeGateway());

      expect(find.text('Mercado'), findsOneWidget);

      await tester.tap(find.text(t.ia_insights.recategorize.propose));
      await tester.pumpAndSettle();

      expect(
        find.text(t.ia_insights.recategorize.proposed_to(category: 'Comida')),
        findsOneWidget,
      );
      expect(
        find.text(
          t.ia_insights.recategorize.proposed_to(category: 'Transporte'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(t.ia_insights.recategorize.proposed_to(category: 'Ocio')),
        findsOneWidget,
      );
    },
  );

  testWidgets('writes only the proposals that stay checked', (tester) async {
    await pumpPage(tester, fakeGateway());

    await tester.tap(find.text(t.ia_insights.recategorize.propose));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Uber'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.ia_insights.recategorize.apply));
    await tester.pumpAndSettle();

    expect(applied.map((p) => p.transactionId), ['tx-1', 'tx-3']);
    expect(
      find.text(t.ia_insights.recategorize.applied(count: '2')),
      findsOneWidget,
    );
  });

  testWidgets('asks to set up a provider when proposing without one', (
    tester,
  ) async {
    await pumpPage(
      tester,
      fakeGateway(
        propose: (items) async => throw const AiException(
          AiErrorKind.notConfigured,
          'AI is not configured',
        ),
      ),
    );

    await tester.tap(find.text(t.ia_insights.recategorize.propose));
    await tester.pumpAndSettle();

    expect(find.text(t.ia_insights.not_configured), findsOneWidget);
    expect(applied, isEmpty);
  });
}
