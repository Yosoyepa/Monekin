import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';
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
    Future<Map<String, String>> Function(List<String> ids)? previous,
  }) {
    return RecategorizeGateway(
      loadItems: (filter) async => _items,
      loadCatalog: () async => _catalog,
      propose: propose ?? (items) async => _proposals,
      loadPreviousCategories: previous,
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
    // A tall screen, so every row and button is built without scrolling.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(ChanchiMascot.preload);
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

  testWidgets('proposals arrive unchecked and Apply changes nothing', (
    tester,
  ) async {
    await pumpPage(
      tester,
      fakeGateway(
        previous: (ids) async => {
          'tx-1': 'Hogar',
          'tx-2': 'Ocio',
          'tx-3': 'Comida',
        },
      ),
    );

    await tester.tap(find.text(t.ia_insights.recategorize.propose));
    await tester.pumpAndSettle();

    for (final title in ['Mercado', 'Uber', 'Cine']) {
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, title),
            )
            .value,
        isFalse,
        reason: '$title must not be preselected',
      );
    }
    // Each row says the category it has now and the one proposed.
    expect(
      find.text(
        t.ia_insights.recategorize.changed_to(
          previous: 'Hogar',
          category: 'Comida',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        t.ia_insights.recategorize.changed_to(
          previous: 'Comida',
          category: 'Ocio',
        ),
      ),
      findsOneWidget,
    );

    final apply = find.widgetWithText(
      FilledButton,
      t.ia_insights.recategorize.apply,
    );
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await tester.tap(apply, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(applied, isEmpty);
  });

  testWidgets('writes only the proposals the user checks', (tester) async {
    await pumpPage(tester, fakeGateway());

    await tester.tap(find.text(t.ia_insights.recategorize.propose));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Mercado'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Cine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.ia_insights.recategorize.apply));
    await tester.pumpAndSettle();

    expect(applied.map((p) => p.transactionId), ['tx-1', 'tx-3']);
    expect(
      find.text(t.ia_insights.recategorize.applied(count: '2')),
      findsOneWidget,
    );
  });

  testWidgets('Select all is an explicit action that checks every row', (
    tester,
  ) async {
    await pumpPage(tester, fakeGateway());

    await tester.tap(find.text(t.ia_insights.recategorize.propose));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recategorize-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.ia_insights.recategorize.apply));
    await tester.pumpAndSettle();

    expect(applied.map((p) => p.transactionId), ['tx-1', 'tx-2', 'tx-3']);
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
