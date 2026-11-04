import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/features_ia/inbox/attachment_thumbnail.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_page.dart';
import 'package:monekin/features_ia/inbox/inbox_review_page.dart';
import 'package:monekin/features_ia/core/dedupe/dedupe.dart' as dedupe;
import 'package:monekin/i18n/generated/translations.g.dart';

import '../../brand/brand_test_utils.dart';
import 'inbox_review_page_test.dart'
    show FakeInboxService, FakeLookup, fakeParse, sampleItem;

/// A host route that opens [page] on top, like the app does.
/// The brand theme with the translations, like main.dart.
Widget app(Widget home, {bool dark = false, bool reduceMotion = false}) =>
    TranslationProvider(
      child: brandApp(home, dark: dark, disableAnimations: reduceMotion),
    );

Widget host(Widget page, {bool reduceMotion = false, bool dark = false}) => app(
  Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => page)),
          child: const Text('open'),
        ),
      ),
    ),
  ),
  dark: dark,
  reduceMotion: reduceMotion,
);

InboxItem receiptWithPhoto(String photoPath) => InboxItem(
  id: 'item-1',
  source: InboxSource.receipt,
  // The stored reference of a receipt is the file name of the photo.
  sourceRef: 'f3a2b7c1-9d4e-4c1a-8b55-0a1e2d3c4b5a.jpg',
  status: InboxStatus.pending,
  createdAt: DateTime(2026, 10, 20, 13, 30),
  attachmentPaths: [photoPath],
  proposals: sampleItem().proposals,
);

InboxReviewPage reviewOf(FakeInboxService service) => InboxReviewPage(
  itemId: 'item-1',
  service: service,
  lookup: FakeLookup(),
  parseAmount: fakeParse,
);

Finder moneyText(int row) => find.descendant(
  of: find.byKey(Key('inbox-money-$row')),
  matching: find.byType(Text),
);

/// True when the first list item is wrapped in its entrance animation.
bool entersAnimated(WidgetTester tester) {
  Widget? first;
  tester.element(find.byType(StaggeredEntrance).first).visitChildren((child) {
    first = child.widget;
  });
  return first is AnimatedBuilder;
}

Future<void> openPage(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;

  setUpAll(loadBrandFonts);

  setUp(() => tmp = Directory.systemTemp.createTempSync('inbox_ui_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String photo() {
    final file = File('${tmp.path}/f3a2b7c1.jpg')
      ..writeAsBytesSync(List.filled(16, 1));
    return file.path;
  }

  testWidgets('the review header shows the merchant, never the file name', (
    tester,
  ) async {
    final service = FakeInboxService(receiptWithPhoto(photo()));

    await tester.pumpWidget(host(reviewOf(service)));
    await openPage(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('inbox-title'))).data,
      'KFC',
    );
    expect(find.textContaining('f3a2b7c1'), findsNothing);
    expect(find.textContaining('.jpg'), findsNothing);
    expect(find.byKey(const Key('inbox-attachment')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == inboxPhotoHeroTag('item-1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the amount shows in the currency format with tabular figures', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(reviewOf(FakeInboxService(receiptWithPhoto(photo())))),
    );
    await openPage(tester);

    final money = tester.widget<Text>(moneyText(0));

    expect(money.data, r'$12,000.00');
    expect(money.style?.fontFeatures, tabularFigures);

    await tester.enterText(find.byKey(const Key('inbox-amount-0')), '45.900');
    await tester.pump();

    expect(tester.widget<Text>(moneyText(0)).data, r'$45,900.00');
  });

  testWidgets('a duplicate shows as a soft warning card', (tester) async {
    final service = FakeInboxService(receiptWithPhoto(photo()))
      ..previewed = const [
        DuplicateWarning(
          rowIndex: 0,
          existingTransactionId: 'tx-old',
          reason: dedupe.duplicateOfExisting,
        ),
      ];

    await tester.pumpWidget(host(reviewOf(service)));
    await openPage(tester);

    expect(find.byKey(const Key('inbox-duplicate-0')), findsOneWidget);
    expect(find.byKey(const Key('inbox-force-0')), findsOneWidget);
  });

  testWidgets('confirming shows Chanchi happy for 1.2 s and then closes', (
    tester,
  ) async {
    await tester.runAsync(ChanchiMascot.preload);
    final service = FakeInboxService(receiptWithPhoto(photo()));

    await tester.pumpWidget(host(reviewOf(service)));
    await openPage(tester);

    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('inbox-celebration')), findsOneWidget);
    expect(
      tester.widget<ChanchiMascot>(find.byType(ChanchiMascot)).mood,
      ChanchiMood.happy,
    );
    expect(service.confirmCalls, hasLength(1));

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byType(InboxReviewPage), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(InboxReviewPage), findsNothing);
  });

  testWidgets('with reduced motion the confirmation closes without waiting', (
    tester,
  ) async {
    final service = FakeInboxService(receiptWithPhoto(photo()));

    await tester.pumpWidget(host(reviewOf(service), reduceMotion: true));
    await openPage(tester);

    await tester.tap(find.text('Confirm'));
    await tester.pump();
    // Only the page fade (150 ms) passes, far less than the 1.2 s of Chanchi.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(InboxReviewPage), findsNothing);
    expect(find.byType(ChanchiMascot), findsNothing);
  });

  testWidgets('a confirmation with a duplicate stays on the result card', (
    tester,
  ) async {
    final service = _SkippingService(receiptWithPhoto(photo()));

    await tester.pumpWidget(host(reviewOf(service)));
    await openPage(tester);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inbox-result')), findsOneWidget);
    expect(find.byKey(const Key('inbox-celebration')), findsNothing);
  });

  group('inbox list', () {
    InboxPage pageOf(FakeInboxService service) =>
        InboxPage(service: service, lookup: FakeLookup());

    testWidgets('items enter staggered, and not at all with reduced motion', (
      tester,
    ) async {
      final service = FakeInboxService(sampleItem());

      await tester.pumpWidget(app(pageOf(service)));
      await tester.pump();
      await tester.pump();
      expect(entersAnimated(tester), isTrue);
      await tester.pumpAndSettle();

      // A fresh tree, so the entrance states start again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(pageOf(FakeInboxService(sampleItem())), reduceMotion: true),
      );
      await tester.pump();
      await tester.pump();
      expect(entersAnimated(tester), isFalse);
    });

    testWidgets(
      'the empty inbox shows Chanchi sleepy, a line and the scan button',
      (tester) async {
        await tester.runAsync(ChanchiMascot.preload);
        var scans = 0;
        final service = FakeInboxService(sampleItem())
          ..item = InboxItem(
            id: 'x',
            source: InboxSource.receipt,
            sourceRef: 'x',
            status: InboxStatus.processed,
            createdAt: DateTime(2026),
            proposals: const [],
          );

        await tester.pumpWidget(
          app(
            InboxPage(
              service: service,
              lookup: FakeLookup(),
              onScan: (_) => scans++,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<ChanchiMascot>(find.byType(ChanchiMascot)).mood,
          ChanchiMood.sleepy,
        );
        expect(find.text('Nothing waiting for your review'), findsOneWidget);

        await tester.tap(find.text('Scan receipt'));
        expect(scans, 1);
      },
    );
  });
}

/// Confirms by skipping the row as a duplicate and leaving the item pending.
class _SkippingService extends FakeInboxService {
  _SkippingService(super.item);

  @override
  Future<ConfirmResult> confirm(
    String itemId,
    List<ProposedTransaction> rows,
  ) async {
    return const ConfirmResult(
      duplicates: [
        DuplicateWarning(
          rowIndex: 0,
          existingTransactionId: 'tx-old',
          reason: dedupe.duplicateOfExisting,
        ),
      ],
    );
  }
}
