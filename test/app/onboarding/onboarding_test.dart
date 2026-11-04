import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/onboarding/onboarding.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../ui_test_utils.dart';

const _titles = [
  'Tus datos se quedan en tu celular',
  'Foto al recibo y listo',
  'Tú confirmas todo',
];

/// Next button and the slide that follows; the currency tile of the first page
/// reads the database, so it is hidden behind a stand-in for the golden.
Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(() async {
    await loadUiFonts();
    await LocaleSettings.setLocale(AppLocale.es);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';

    testWidgets('three welcome pages ($name)', (tester) async {
      await useSurface(tester, 360, 700, ratio: 2);
      await tester.pumpWidget(
        uiApp(OnboardingPage(onFinished: () {}), dark: dark),
      );
      await settleSvgs(tester);
      await tester.pump(const Duration(milliseconds: 600));

      for (var i = 0; i < 3; i++) {
        expect(find.text(_titles[i]), findsOneWidget);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/onboarding_${i + 1}_$name.png'),
        );
        if (i < 2) await _next(tester);
      }
    });
  }

  testWidgets('the last page continues to the app', (tester) async {
    var finished = false;
    await useSurface(tester, 360, 700);
    await tester.pumpWidget(
      uiApp(OnboardingPage(onFinished: () => finished = true)),
    );
    await settleSvgs(tester);

    await _next(tester);
    await _next(tester);
    expect(finished, isFalse);

    await tester.tap(find.byType(FilledButton));
    expect(finished, isTrue);
  });

  testWidgets('with reduced motion pages are final and change without '
      'sliding', (tester) async {
    await useSurface(tester, 360, 700);
    await tester.pumpWidget(
      uiApp(OnboardingPage(onFinished: () {}), disableAnimations: true),
    );
    await settleSvgs(tester);

    // No fade/scale wrapper on the page content.
    expect(find.byType(Opacity), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // The next page is there right away: no slide in progress.
    expect(find.text(_titles[1]), findsOneWidget);
    expect(find.text(_titles[0]), findsNothing);

    // Let the button animation and stream clean-up timers finish.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
