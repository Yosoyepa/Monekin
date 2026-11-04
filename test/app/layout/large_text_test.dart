import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/layout/widgets/app_bottom_bar.dart';
import 'package:monekin/core/routes/destinations.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../ui_test_utils.dart';

void main() {
  setUpAll(() async {
    await loadUiFonts();
    await LocaleSettings.setLocale(AppLocale.es);
  });

  for (final scale in [1.5, 2.0]) {
    testWidgets('the bottom bar does not overflow at text scale $scale', (
      tester,
    ) async {
      final previous = InboxService.instance;
      InboxService.instance = FakeInbox(Stream.value(7));
      addTearDown(() => InboxService.instance = previous);

      await useSurface(tester, 360, 640);
      await tester.pumpWidget(
        uiApp(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              bottomNavigationBar: AppBottomBar(
                selectedDestination: AppMenuDestinationsID.dashboard,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  }
}
