import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/onboarding/intro.page.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../ui_test_utils.dart';

void main() {
  setUpAll(() async {
    await loadUiFonts();
    await LocaleSettings.setLocale(AppLocale.es);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';

    testWidgets('intro page ($name)', (tester) async {
      await useSurface(tester, 360, 700, ratio: 2);
      await tester.pumpWidget(
        uiApp(const IntroPage(animateMascot: false), dark: dark),
      );
      await settleSvgs(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/intro_$name.png'),
      );
    });
  }

  for (final locale in [AppLocale.es, AppLocale.en]) {
    testWidgets('shows Finanzas IA and never Monekin or offline '
        '(${locale.languageCode})', (tester) async {
      await LocaleSettings.setLocale(locale);
      addTearDown(() => LocaleSettings.setLocale(AppLocale.es));
      await useSurface(tester, 360, 700);
      await tester.pumpWidget(uiApp(const IntroPage(animateMascot: false)));
      await settleSvgs(tester);

      final texts = [
        for (final w in tester.widgetList<Text>(find.byType(Text)))
          w.data ?? w.textSpan?.toPlainText() ?? '',
        // The legal footer is rich text built by `HTMLText`.
        for (final w in tester.widgetList<RichText>(find.byType(RichText)))
          w.text.toPlainText(),
      ].join(' ').toLowerCase();

      expect(texts, contains('finanzas ia'));
      expect(texts, isNot(contains('monekin')));
      expect(texts, isNot(contains('offline')));
      expect(find.byType(ChanchiMascot), findsOneWidget);
    });
  }

  testWidgets('the main button says Empezar and starts the welcome', (
    tester,
  ) async {
    var started = false;
    await useSurface(tester, 360, 700);
    await tester.pumpWidget(
      uiApp(IntroPage(animateMascot: false, onStart: () => started = true)),
    );
    await settleSvgs(tester);

    expect(find.widgetWithText(FilledButton, 'Empezar'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    expect(started, isTrue);
  });
}
