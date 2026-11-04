import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/settings/settings_page.dart';
import 'package:monekin/brand/brand_gallery_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../ui_test_utils.dart';

void main() {
  setUpAll(() async {
    await loadUiFonts();
    await LocaleSettings.setLocale(AppLocale.es);
  });

  testWidgets('the gallery entry is not there when debug is off (release)', (
    tester,
  ) async {
    await tester.pumpWidget(
      uiApp(const Scaffold(body: BrandGalleryTile(debug: false))),
    );

    expect(find.text('Galería de marca'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('the gallery entry opens the gallery in debug', (tester) async {
    await useSurface(tester, 420, 900);
    await tester.pumpWidget(
      uiApp(const Scaffold(body: BrandGalleryTile(debug: true))),
    );

    expect(find.text('Galería de marca'), findsOneWidget);

    await tester.tap(find.text('Galería de marca'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(BrandGalleryPage), findsOneWidget);

    // Leave the gallery so its blinking timers are cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  test('in debug the gallery route exists', () {
    // `kDebugMode` is a compile-time constant, so release can only be checked
    // through the tile's `debug` flag above.
    expect(brandGalleryRoute(), isNotNull);
  });
}
