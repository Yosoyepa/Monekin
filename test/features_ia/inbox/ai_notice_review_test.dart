// Notices (T002, round 3): a notice the app does not understand waits «to read with AI» and is sent only by a tap.
// Also: the review reads the reconciliation of a statement from the data of the item, not from its note.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/features_ia/core/consent/ai_consent_sheet.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_review_page.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../utils/consent_support.dart';
import 'inbox_review_page_test.dart'
    show FakeInboxService, FakeLookup, fakeParse, harness;

const _sentence = 'Movimiento por \$88.500 con TIENDA ****';

InboxItem _waitingNotice() => InboxItem(
  id: 'item-1',
  source: InboxSource.notification,
  sourceRef: 'com.nequi.MobileApp',
  status: InboxStatus.pending,
  createdAt: DateTime(2026, 11, 4, 9),
  proposals: const [],
  rawText: 'Movimiento por \$88.500 con TIENDA 123456789',
  note: 'The app did not understand this notice.',
  data: {InboxDataKeys.aiText: _sentence},
);

void main() {
  late List<InboxItem> read;

  Future<void> pumpPage(
    WidgetTester tester,
    InboxItem item, {
    NoticeReadResult result = NoticeReadResult.read,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(ChanchiMascot.preload);
    await tester.pumpWidget(
      harness(
        InboxReviewPage(
          itemId: item.id,
          service: FakeInboxService(item),
          lookup: FakeLookup(),
          parseAmount: fakeParse,
          readNotice: (item) async {
            read.add(item);
            return result;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => read = []);

  testWidgets('shows the exact sentence and «Read with AI»', (tester) async {
    await useTestConsent();
    await pumpPage(tester, _waitingNotice());

    final t = Translations.of(tester.element(find.byType(InboxReviewPage)));
    expect(find.byKey(const Key('inbox-ai-notice')), findsOneWidget);
    expect(find.text(t.ia_inbox.ai_notice_pending), findsOneWidget);
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('inbox-ai-text')))
          .data,
      _sentence,
    );
    expect(find.text(t.ia_inbox.read_with_ai), findsOneWidget);
    expect(read, isEmpty);
  });

  testWidgets('with consent the tap reads the notice once', (tester) async {
    await useTestConsent();
    await pumpPage(tester, _waitingNotice());

    await tester.tap(find.byKey(const Key('inbox-read-ai')));
    await tester.pumpAndSettle();

    expect(read, hasLength(1));
    expect(read.single.data![InboxDataKeys.aiText], _sentence);
  });

  testWidgets(
    'without consent it asks first, and «No usar IA aquí» sends nothing',
    (tester) async {
      await useTestConsent(grantAll: false);
      await pumpPage(tester, _waitingNotice());

      await tester.tap(find.byKey(const Key('inbox-read-ai')));
      await tester.pumpAndSettle();
      expect(find.byType(AiConsentSheet), findsOneWidget);
      await tester.tap(find.byKey(const Key('consent-decline')));
      await tester.pumpAndSettle();

      expect(read, isEmpty);

      await tester.tap(find.byKey(const Key('inbox-read-ai')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consent-accept')));
      await tester.pumpAndSettle();

      expect(read, hasLength(1));
    },
  );

  testWidgets('when the limit is reached it says so and sends nothing', (
    tester,
  ) async {
    await useTestConsent();
    await pumpPage(tester, _waitingNotice(), result: NoticeReadResult.limit);

    await tester.tap(find.byKey(const Key('inbox-read-ai')));
    await tester.pumpAndSettle();

    final t = Translations.of(tester.element(find.byType(InboxReviewPage)));
    expect(find.text(t.ia_inbox.ai_limit_reached), findsOneWidget);
  });

  testWidgets(
    'BUG-07: a warning of the model about the total shows in the review',
    (tester) async {
      final item = InboxItem(
        id: 'item-1',
        source: InboxSource.receipt,
        sourceRef: 'recibo.jpg',
        status: InboxStatus.pending,
        createdAt: DateTime(2026, 11, 4, 9),
        proposals: [
          ProposedTransaction(
            date: DateTime(2026, 11, 3),
            title: 'RESTAURANTE',
            amount: 1234567,
            categoryId: 'cat-e',
            accountId: 'acc-1',
            warning: 'Hay varios totales: 1.234.567 y 1.122.334',
          ),
        ],
      );

      await pumpPage(tester, item);

      expect(find.textContaining('Hay varios totales'), findsOneWidget);
    },
  );

  testWidgets(
    'a statement shows its reconciliation from the data of the item',
    (tester) async {
      final item = InboxItem(
        id: 'item-1',
        source: InboxSource.statement,
        sourceRef: 'extracto-nov',
        status: InboxStatus.pending,
        createdAt: DateTime(2026, 11, 4, 9),
        proposals: [
          ProposedTransaction(
            date: DateTime(2026, 11, 1),
            title: 'EXITO',
            amount: 45900,
            categoryId: 'cat-e',
            accountId: 'acc-1',
          ),
        ],
        // No figures in the note: only the data can feed the card.
        note: 'Anything the importer wrote here',
        data: {InboxDataKeys.net: -45900.0, InboxDataKeys.difference: 100.0},
      );

      await pumpPage(tester, item);

      expect(find.byKey(const Key('reconciliation-card')), findsOneWidget);
      expect(find.byKey(const Key('reconciliation-net')), findsOneWidget);
      expect(
        find.byKey(const Key('reconciliation-difference')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('inbox-note')), findsNothing);
    },
  );
}
