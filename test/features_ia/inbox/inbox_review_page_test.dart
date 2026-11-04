import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/core/dedupe/dedupe.dart' as dedupe;
import 'package:monekin/features_ia/inbox/drift_inbox_service.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_page.dart';
import 'package:monekin/features_ia/inbox/inbox_review_page.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class FakeInboxService extends NotReadyInboxService
    implements InboxDuplicatePreview {
  FakeInboxService(this.item);

  InboxItem item;
  final confirmCalls = <List<ProposedTransaction>>[];
  var discarded = false;
  var previewed = <DuplicateWarning>[];

  @override
  Future<List<DuplicateWarning>> previewDuplicates(
    List<ProposedTransaction> rows,
  ) async => previewed;

  @override
  Future<InboxItem?> getItem(String id) async => item;

  @override
  Stream<List<InboxItem>> watchItems({InboxStatus? status}) =>
      Stream.value([if (status == null || status == item.status) item]);

  @override
  Future<ConfirmResult> confirm(
    String itemId,
    List<ProposedTransaction> rows,
  ) async {
    confirmCalls.add([
      for (final r in rows)
        ProposedTransaction(
          date: r.date,
          title: r.title,
          amount: r.amount,
          type: r.type,
          categoryId: r.categoryId,
          accountId: r.accountId,
          allowDuplicate: r.allowDuplicate,
        ),
    ]);

    item = InboxItem(
      id: item.id,
      source: item.source,
      sourceRef: item.sourceRef,
      status: InboxStatus.processed,
      createdAt: item.createdAt,
      proposals: rows,
      resultTransactionIds: ['tx-1'],
    );

    return const ConfirmResult(createdIds: ['tx-1']);
  }

  @override
  Future<void> discard(String itemId, {String? reason}) async =>
      discarded = true;
}

class FakeLookup implements InboxReviewLookup {
  final account_ = Account.fromDB(
    AccountInDB(
      id: 'acc-1',
      name: 'Bancolombia',
      iniValue: 0,
      date: DateTime(2020),
      type: AccountType.money,
      isSaving: false,
      trackingMode: AccountTrackingMode.transactions,
      iconId: 'wallet',
      displayOrder: 0,
      currencyId: 'COP',
    ),
    const CurrencyInDB(
      code: 'COP',
      symbol: r'$',
      name: 'Peso',
      decimalPlaces: 2,
      isDefault: true,
      type: 0,
    ),
  );

  final category_ = Category(
    id: 'cat-e',
    name: 'Comida',
    iconId: 'wallet',
    displayOrder: 0,
    color: '4385be',
    type: CategoryType.E,
  );

  @override
  Future<Account?> account(String id) async => account_;

  @override
  Future<Category?> category(String id) async => category_;

  @override
  Future<Account?> pickAccount(BuildContext context, Account? current) async =>
      account_;

  @override
  Future<Category?> pickCategory(
    BuildContext context,
    Category? current,
    TransactionType type,
  ) async => category_;

  @override
  Future<Category?> pickAnyCategory(BuildContext context) async => category_;
}

/// Same rule as the real parser for the cases of this test (`45.900` = 45900,
/// `12,34` = 12.34), so the page can be tested before w-utils lands.
double? fakeParse(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(text)) {
    return double.parse(text.replaceAll('.', ''));
  }
  return double.tryParse(text.replaceAll(',', '.'));
}

InboxItem sampleItem() => InboxItem(
  id: 'item-1',
  source: InboxSource.receipt,
  sourceRef: 'recibo-01.jpg',
  status: InboxStatus.pending,
  createdAt: DateTime(2026, 10, 20, 13, 30),
  proposals: [
    ProposedTransaction(
      date: DateTime(2026, 10, 20, 13, 30),
      title: 'KFC',
      amount: 12000,
      categoryId: 'cat-e',
      accountId: 'acc-1',
    ),
  ],
);

Widget harness(Widget page) =>
    TranslationProvider(child: MaterialApp(home: page));

void main() {
  testWidgets('editing the amount to 45.900 confirms the row with 45900', (
    tester,
  ) async {
    final service = FakeInboxService(sampleItem());

    await tester.pumpWidget(
      harness(
        InboxReviewPage(
          itemId: 'item-1',
          service: service,
          lookup: FakeLookup(),
          parseAmount: fakeParse,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bancolombia'), findsOneWidget);
    expect(find.text('Comida'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('inbox-amount-0')), '45.900');
    await tester.enterText(
      find.byKey(const Key('inbox-title-0')),
      'KFC Unicentro',
    );
    await tester.pump();

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(service.confirmCalls, hasLength(1));
    final row = service.confirmCalls.single.single;
    expect(row.amount, 45900);
    expect(row.title, 'KFC Unicentro');
    expect(row.categoryId, 'cat-e');
    expect(row.accountId, 'acc-1');

    // Everything was created: the page celebrates and then closes by itself.
    expect(find.byType(InboxReviewPage), findsNothing);
  });

  testWidgets('an amount that is not valid disables Confirm', (tester) async {
    final service = FakeInboxService(sampleItem());

    await tester.pumpWidget(
      harness(
        InboxReviewPage(
          itemId: 'item-1',
          service: service,
          lookup: FakeLookup(),
          parseAmount: fakeParse,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('inbox-amount-0')), 'abc');
    await tester.pump();

    expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );
    expect(service.confirmCalls, isEmpty);
  });

  testWidgets(
    'a row without account or category shows the missing-data warnings',
    (tester) async {
      final item = sampleItem();
      item.proposals.single
        ..accountId = null
        ..categoryId = null;

      await tester.pumpWidget(
        harness(
          InboxReviewPage(
            itemId: 'item-1',
            service: FakeInboxService(item),
            lookup: FakeLookup(),
            parseAmount: fakeParse,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Once as warning and once as the placeholder of the selector.
      expect(find.text('Choose an account'), findsNWidgets(2));
      expect(find.text('Choose a category'), findsNWidgets(2));
    },
  );

  testWidgets('Discard calls the service', (tester) async {
    final service = FakeInboxService(sampleItem());

    await tester.pumpWidget(
      harness(
        InboxReviewPage(
          itemId: 'item-1',
          service: service,
          lookup: FakeLookup(),
          parseAmount: fakeParse,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(service.discarded, isTrue);
  });

  testWidgets('the inbox lists the items of the selected tab and opens one', (
    tester,
  ) async {
    final service = FakeInboxService(sampleItem());
    String? opened;

    await tester.pumpWidget(
      harness(
        InboxPage(
          service: service,
          lookup: FakeLookup(),
          onOpenItem: (context, id) => opened = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The card shows the merchant, never the file name of the photo.
    expect(find.text('KFC'), findsOneWidget);
    expect(find.text('recibo-01.jpg'), findsNothing);
    expect(find.text('Pending'), findsWidgets);

    await tester.tap(find.text('KFC'));
    expect(opened, 'item-1');

    await tester.tap(find.text('Processed'));
    await tester.pumpAndSettle();

    expect(find.text('KFC'), findsNothing);
    expect(find.text('No processed items yet'), findsOneWidget);
  });

  testWidgets('shows the note and the original text of the item', (
    tester,
  ) async {
    final item = InboxItem(
      id: 'item-1',
      source: InboxSource.notification,
      sourceRef: 'com.nequi.MobileApp',
      status: InboxStatus.pending,
      createdAt: DateTime(2026, 10, 20),
      proposals: const [],
      rawText: 'Pagaste 45.900 en KFC con tu tarjeta',
      note: 'No se pudo interpretar el aviso',
    );

    await tester.pumpWidget(
      harness(
        InboxReviewPage(
          itemId: 'item-1',
          service: FakeInboxService(item),
          lookup: FakeLookup(),
          parseAmount: fakeParse,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inbox-note')), findsOneWidget);
    expect(find.text('No se pudo interpretar el aviso'), findsOneWidget);
    expect(find.byKey(const Key('inbox-raw-text')), findsOneWidget);
    expect(find.text('Pagaste 45.900 en KFC con tu tarjeta'), findsOneWidget);
  });

  testWidgets('an item without rows lets the user add one by hand or discard', (
    tester,
  ) async {
    final item = InboxItem(
      id: 'item-1',
      source: InboxSource.notification,
      sourceRef: 'com.nequi.MobileApp',
      status: InboxStatus.pending,
      createdAt: DateTime(2026, 10, 20),
      proposals: const [],
      rawText: 'Pagaste 45.900 en KFC',
    );
    final service = FakeInboxService(item);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        InboxReviewPage(
          itemId: 'item-1',
          service: service,
          lookup: FakeLookup(),
          parseAmount: fakeParse,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inbox-amount-0')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
      reason: 'nothing to confirm yet',
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Discard'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('inbox-add-row')));
    await tester.pumpAndSettle();

    // The new row has no amount yet, so it cannot be confirmed as is.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const Key('inbox-title-0')), 'KFC');
    await tester.enterText(find.byKey(const Key('inbox-amount-0')), '45.900');
    await tester.ensureVisible(find.byKey(const Key('inbox-category-0')));
    await tester.tap(find.byKey(const Key('inbox-category-0')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('inbox-account-0')));
    await tester.tap(find.byKey(const Key('inbox-account-0')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    final row = service.confirmCalls.single.single;
    expect(row.title, 'KFC');
    expect(row.amount, 45900);
    expect(row.categoryId, 'cat-e');
    expect(row.accountId, 'acc-1');
  });

  testWidgets('a duplicate shows its reason and is only created when forced', (
    tester,
  ) async {
    final service = FakeInboxService(sampleItem())
      ..previewed = const [
        DuplicateWarning(
          rowIndex: 0,
          existingTransactionId: 'tx-old',
          reason: dedupe.duplicateOfExisting,
        ),
      ];

    await tester.pumpWidget(
      harness(
        InboxReviewPage(
          itemId: 'item-1',
          service: service,
          lookup: FakeLookup(),
          parseAmount: fakeParse,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('matches an existing transaction'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('inbox-force-0')))
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('inbox-force-0')));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(service.confirmCalls.single.single.allowDuplicate, isTrue);
  });

  testWidgets(
    'without ticking Create anyway the row goes as a plain duplicate',
    (tester) async {
      final service = FakeInboxService(sampleItem())
        ..previewed = const [
          DuplicateWarning(
            rowIndex: 0,
            existingTransactionId: '',
            reason: 'same row twice',
          ),
        ];

      await tester.pumpWidget(
        harness(
          InboxReviewPage(
            itemId: 'item-1',
            service: service,
            lookup: FakeLookup(),
            parseAmount: fakeParse,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(service.confirmCalls.single.single.allowDuplicate, isFalse);
    },
  );
  testWidgets('created rows are locked and expose a transaction link', (
    tester,
  ) async {
    final item = sampleItem();
    item.proposals.single.status = ProposalStatus.created;
    item.proposals.single.transactionId = 'tx-1';
    item.proposals.add(
      ProposedTransaction(
        date: DateTime(2026, 10, 20),
        title: 'To fix',
        amount: 20,
      ),
    );
    await tester.pumpWidget(
      harness(
        InboxReviewPage(
          itemId: item.id,
          service: FakeInboxService(item),
          lookup: FakeLookup(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const Key('inbox-title-0'))).enabled,
      isFalse,
    );
    expect(find.byKey(const Key('inbox-remove-0')), findsNothing);
    expect(find.byKey(const Key('inbox-created-0')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('inbox-title-1')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('inbox-title-1'))).enabled,
      isTrue,
    );
  });

  testWidgets('batch duplicate is visibly enabled by default', (tester) async {
    final service = FakeInboxService(sampleItem())
      ..previewed = const [
        DuplicateWarning(
          rowIndex: 0,
          existingTransactionId: '',
          reason: dedupe.duplicateInBatch,
        ),
      ];
    await tester.pumpWidget(
      harness(
        InboxReviewPage(
          itemId: 'item-1',
          service: service,
          lookup: FakeLookup(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('matches another row in this batch'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('inbox-force-0')))
          .value,
      isTrue,
    );
  });

  testWidgets(
    'the bulk action fills the expense rows and leaves the income row',
    (tester) async {
      final item = InboxItem(
        id: 'item-1',
        source: InboxSource.statement,
        sourceRef: 'nequi-2026-10',
        status: InboxStatus.pending,
        createdAt: DateTime(2026, 10, 20),
        proposals: [
          ProposedTransaction(
            date: DateTime(2026, 10, 2),
            title: 'Recarga celular',
            amount: 20000,
            accountId: 'acc-1',
          ),
          ProposedTransaction(
            date: DateTime(2026, 10, 5),
            title: 'Pago en tienda',
            amount: 14500,
            accountId: 'acc-1',
          ),
          ProposedTransaction(
            date: DateTime(2026, 10, 13),
            title: 'Recepcion de Maria Lopez',
            amount: 80000,
            type: TransactionType.income,
            accountId: 'acc-1',
          ),
        ],
      );
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          InboxReviewPage(
            itemId: 'item-1',
            service: FakeInboxService(item),
            lookup: FakeLookup(),
            parseAmount: fakeParse,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Choose a category for 3 rows without one'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('inbox-bulk-category')));
      await tester.tap(find.byKey(const Key('inbox-bulk-category')));
      await tester.pumpAndSettle();

      Finder categoryTile(int index, String text) => find.descendant(
        of: find.byKey(Key('inbox-category-$index')),
        matching: find.text(text),
      );
      expect(categoryTile(0, 'Comida'), findsOneWidget);
      expect(categoryTile(1, 'Comida'), findsOneWidget);
      expect(categoryTile(2, 'Choose a category'), findsOneWidget);

      expect(
        find.text('Choose a category for 1 row without one'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Category applied to 2 rows. 1 row does not accept this category and stays without one.',
        ),
        findsOneWidget,
      );
    },
  );

  test('the real parser reads 45.900 as 45900', () {
    double? parsed;
    try {
      parsed = parseLocalizedAmount('45.900');
    } on UnimplementedError {
      markTestSkipped('parseLocalizedAmount is not merged yet (w-utils)');
      return;
    }

    expect(parsed, 45900);
  });
}
