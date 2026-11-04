// Goldens of the consent sheet and of the exact-text preview at 360 dp, in light and dark.
//
// Generated on Windows: text may differ by a pixel on another OS.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/core/consent/ai_consent_sheet.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../../brand/brand_test_utils.dart';

const _width = 360.0;

const _gemini = AiProviderConfig(
  provider: AiProviderId.gemini,
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  model: 'gemini-flash-lite-latest',
);

const _statementText = '''
01/11/2026 EXITO UNICENTRO -45.900
02/11/2026 NOMINA EMPRESA [id] 3.000.000
03/11/2026 UBER TRIP -32.500
04/11/2026 NETFLIX.COM -38.900
05/11/2026 RETIRO CAJERO [id] -200.000
Saldo inicial 100.000
Saldo final 2.782.700''';

Widget _app(Widget home, {required bool dark}) => TranslationProvider(
  child: brandApp(home, dark: dark, disableAnimations: true),
);

/// Loads the Material icon font of the SDK and a monospace font, so goldens draw icons and the preview text, not boxes.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final iconLoader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await iconLoader.load();

  final consolas = File('C:/Windows/Fonts/consola.ttf');
  if (consolas.existsSync()) {
    for (final family in ['monospace', 'Consolas']) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(consolas.readAsBytesSync())),
        );
      await loader.load();
    }
  }
}

Future<void> _surface(WidgetTester tester, double height) async {
  await tester.binding.setSurfaceSize(Size(_width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  setUpAll(() async {
    await loadBrandFonts();
    await _loadFonts();
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';

    testWidgets('consent sheet $name', (tester) async {
      await _surface(tester, 760);
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: SafeArea(
              child: AiConsentSheet(
                feature: AiFeature.statement,
                config: _gemini,
              ),
            ),
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/consent_sheet_$name.png'),
      );
    });

    testWidgets('preview of the exact text $name', (tester) async {
      await _surface(tester, 640);
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: SafeArea(
              child: AiPreviewSheet(text: _statementText, config: _gemini),
            ),
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/preview_sheet_$name.png'),
      );
    });
  }
}
