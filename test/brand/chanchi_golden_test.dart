import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';

import 'brand_test_utils.dart';

void main() {
  setUpAll(loadBrandFonts);

  for (final mood in ChanchiMood.values) {
    testWidgets('ChanchiMascot ${mood.name} final frame', (tester) async {
      await tester.binding.setSurfaceSize(const Size(200, 190));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        brandApp(
          Scaffold(
            body: Center(
              child: ChanchiMascot(mood: mood, size: 160, animate: false),
            ),
          ),
        ),
      );
      await settleSvgs(tester);

      await expectLater(
        find.byType(ChanchiMascot),
        matchesGoldenFile('goldens/chanchi_${mood.name}.png'),
      );
    });
  }
}
