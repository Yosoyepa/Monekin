import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/brand_gallery_page.dart';

import 'brand_test_utils.dart';

void main() {
  setUpAll(loadBrandFonts);

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';

    testWidgets('brand gallery $name', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        brandApp(const BrandGalleryPage(animate: false), dark: dark),
      );
      await settleSvgs(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/brand_gallery_$name.png'),
      );
    });
  }
}
