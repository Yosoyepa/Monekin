import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/core/presentation/theme.dart';

/// Loads the bundled Nunito so goldens show real text instead of boxes.
Future<void> loadBrandFonts() async {
  final loader = FontLoader('Nunito');
  for (final file in ['Regular', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/Nunito/Nunito-$file.ttf'));
  }
  await loader.load();
}

/// App wrapper that uses the brand theme, like main.dart does.
Widget brandApp(
  Widget home, {
  bool dark = false,
  bool disableAnimations = false,
}) {
  return Builder(
    builder: (context) {
      final theme = getThemeData(
        context,
        isDark: dark,
        amoledMode: false,
        lightDynamic: null,
        darkDynamic: null,
        accentColor: 'auto',
      );

      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: home,
      );
    },
  );
}

/// Loads the SVG layers and lets them paint (the loaders do real async I/O).
Future<void> settleSvgs(WidgetTester tester) async {
  await tester.runAsync(ChanchiMascot.preload);
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
