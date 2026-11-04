// The AI screens at 360 and 412 dp with large system text: nothing overflows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/features_ia/inbox/inbox_page.dart';
import 'package:monekin/features_ia/inbox/inbox_review_page.dart';
import 'package:monekin/features_ia/statements/reconciliation_card.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../../brand/brand_test_utils.dart';
import '../inbox/inbox_review_page_test.dart'
    show FakeInboxService, FakeLookup, fakeParse, sampleItem;

void main() {
  setUpAll(loadBrandFonts);

  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 1.4]) {
      final label = '${width.toInt()} dp, text x$scale';

      Widget app(Widget home) => TranslationProvider(
        child: brandApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: home,
            ),
          ),
        ),
      );

      testWidgets('inbox, review and reconciliation fit at $label', (
        tester,
      ) async {
        await tester.runAsync(ChanchiMascot.preload);
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = FakeInboxService(sampleItem());

        await tester.pumpWidget(
          app(InboxPage(service: service, lookup: FakeLookup())),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          app(
            InboxReviewPage(
              itemId: 'item-1',
              service: service,
              lookup: FakeLookup(),
              parseAmount: fakeParse,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          app(
            Scaffold(
              body: ReconciliationCard(
                reconciliation: (net: -62300.5, difference: 1200.0),
                format: iaMoneyFormat(symbol: r'$', decimals: 2),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
