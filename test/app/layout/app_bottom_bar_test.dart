import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/layout/widgets/app_bottom_bar.dart';
import 'package:monekin/app/layout/widgets/scan_receipt_button.dart';
import 'package:monekin/core/routes/destinations.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../ui_test_utils.dart';

Widget _bar({bool dark = false, bool reduce = false}) => uiApp(
  const Scaffold(
    bottomNavigationBar: AppBottomBar(
      selectedDestination: AppMenuDestinationsID.dashboard,
    ),
  ),
  dark: dark,
  disableAnimations: reduce,
);

void main() {
  late InboxService previous;
  late StreamController<int> pending;

  /// A stream event needs one pump to arrive and another to be painted.
  Future<void> emit(WidgetTester tester, int count) async {
    pending.add(count);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  setUpAll(() async {
    await loadUiFonts();
    await LocaleSettings.setLocale(AppLocale.es);
  });

  setUp(() {
    previous = InboxService.instance;
    pending = StreamController<int>.broadcast();
    InboxService.instance = FakeInbox(pending.stream);
  });

  tearDown(() async {
    InboxService.instance = previous;
    await pending.close();
  });

  testWidgets('the center button opens the receipt capture', (tester) async {
    await useSurface(tester, 360, 640);
    await tester.pumpWidget(_bar());

    expect(find.byTooltip('Escanear recibo'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(
      tester.getSize(find.byType(FloatingActionButton)),
      const Size(56, 56),
    );

    await tester.tap(find.byType(ScanReceiptButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Without a configured AI, `startReceiptCapture` offers the AI settings.
    final t = Translations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(t.ia_receipts.not_configured_title), findsOneWidget);
  });

  testWidgets('the center button keeps the old hero tag', (tester) async {
    await useSurface(tester, 360, 640);
    await tester.pumpWidget(_bar());

    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.heroTag, scanReceiptHeroTag);
  });

  testWidgets('the inbox badge follows watchPendingCount', (tester) async {
    await useSurface(tester, 360, 640);
    await tester.pumpWidget(_bar());

    expect(find.text('3'), findsNothing);

    await emit(tester, 3);
    expect(find.text('3'), findsOneWidget);

    await emit(tester, 120);
    expect(find.text('99+'), findsOneWidget);

    await emit(tester, 0);
    expect(find.text('99+'), findsNothing);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('the bar has the four destinations with the scan button '
      'between', (tester) async {
    await useSurface(tester, 360, 640);
    await tester.pumpWidget(_bar());

    final labels = ['Inicio', 'Movimientos', 'Bandeja', 'Más'];
    final xs = [for (final l in labels) tester.getCenter(find.text(l)).dx];
    final scanX = tester.getCenter(find.byType(ScanReceiptButton)).dx;

    expect(xs, orderedEquals([...xs]..sort()));
    expect(xs[1] < scanX && scanX < xs[2], isTrue);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';

    testWidgets('bottom bar with the scan button and the counter ($name)', (
      tester,
    ) async {
      await useSurface(tester, 360, 160, ratio: 2);
      await tester.pumpWidget(_bar(dark: dark));
      await emit(tester, 3);
      await tester.pump(const Duration(milliseconds: 500));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/bottom_bar_$name.png'),
      );
    });
  }
}
