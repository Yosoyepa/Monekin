// Goldens of the backup password sheets at 360 dp, in light and dark.
//
// Generated on Windows: text may differ by a pixel on another OS.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_password_sheets.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../../brand/brand_test_utils.dart';

const _width = 360.0;

/// Loads the Material icon font of the SDK, so goldens draw icons, not boxes.
Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final bytes = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Widget _app(Widget sheet, {required bool dark}) => TranslationProvider(
  child: brandApp(
    Builder(
      builder: (context) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Align(alignment: Alignment.bottomCenter, child: sheet),
      ),
    ),
    dark: dark,
    disableAnimations: true,
  ),
);

Future<void> _surface(WidgetTester tester, double height) async {
  await tester.binding.setSurfaceSize(Size(_width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  setUpAll(() async {
    await loadBrandFonts();
    await _loadIcons();
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';

    testWidgets('create password sheet, $name', (tester) async {
      await _surface(tester, 470);
      await tester.pumpWidget(
        _app(const CreateBackupPasswordSheet(), dark: dark),
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Chanchi-2026-ahorro');
      await tester.enterText(fields.at(1), 'Chanchi-2026-ahorro');
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/create_password_$name.png'),
      );
    });

    testWidgets('restore password prompt after a wrong one, $name', (
      tester,
    ) async {
      await _surface(tester, 280);
      await tester.pumpWidget(
        _app(const RestorePasswordSheet(wrongBefore: true), dark: dark),
      );

      await tester.enterText(find.byType(TextField), 'mi clave vieja');
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/restore_password_$name.png'),
      );
    });
  }
}
