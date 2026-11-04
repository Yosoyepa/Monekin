// Flow 14 of the Finanzas IA emulator E2E (T002, round 2): the brand migration and the look of the new screens.
// A base that still holds `accentColor = 'auto'` (the old factory default) starts with the brand accent; the home
// is captured in light and dark mode, and so is the welcome screen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/app/layout/page_switcher.dart';
import 'package:monekin/brand/brand_migration.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/core/database/services/app-data/app_data_service.dart';
import 'package:monekin/core/database/services/user-setting/user_setting_service.dart';
import 'package:monekin/main.dart' as app;
import 'package:path_provider/path_provider.dart';

import 'support/e2e_support.dart';

Future<File> migrationMarker() async => File(
  '${(await getApplicationDocumentsDirectory()).path}/$brandMigrationFileName',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flow 14: accentColor auto migrates to the brand accent, once', (
    tester,
  ) async {
    // An install of the old version: dynamic colors as the default and no migration marker yet.
    await UserSettingService.instance.setItem(SettingKey.accentColor, 'auto');
    final marker0 = await migrationMarker();
    if (await marker0.exists()) await marker0.delete();
    marker('before boot: accentColor=auto, marker file removed');

    await bootApp(tester);
    final accent = appStateSettings[SettingKey.accentColor];
    marker(
      'after boot: accentColor=$accent, marker exists=${await marker0.exists()}',
    );
    expect(accent, BrandTokens.accentHex);
    expect(await marker0.exists(), isTrue);
    expect(jsonDecode(await marker0.readAsString()), {'done': true});
    final primary = Theme.of(
      tester.element(find.byType(PageSwitcher)),
    ).colorScheme.primary;
    marker('theme primary=${primary.toARGB32().toRadixString(16)}');
    expect(
      primary.toARGB32() & 0xFFFFFF,
      int.parse(BrandTokens.accentHex, radix: 16),
      reason: 'the home does not use the brand accent',
    );
    await shot(tester, 'R2_14_home_light');

    // The user turns dynamic colors back on: the next start keeps them.
    await UserSettingService.instance.setItem(SettingKey.accentColor, 'auto');
    await runBrandMigration();
    expect(appStateSettings[SettingKey.accentColor], 'auto');
    marker(
      'dynamic colors chosen later are kept: ${appStateSettings[SettingKey.accentColor]}',
    );
    await UserSettingService.instance.setItem(
      SettingKey.accentColor,
      BrandTokens.accentHex,
    );

    // Home in dark mode.
    final previousMode = appStateSettings[SettingKey.themeMode];
    await UserSettingService.instance.setItem(SettingKey.themeMode, 'dark');
    app.appStateKey.currentState?.refreshAppState();
    await pumpFor(tester, const Duration(seconds: 3));
    expect(
      Theme.of(tester.element(find.byType(PageSwitcher))).brightness,
      Brightness.dark,
    );
    await shot(tester, 'R2_14_home_dark');
    await UserSettingService.instance.setItem(
      SettingKey.themeMode,
      previousMode ?? 'system',
    );
    app.appStateKey.currentState?.refreshAppState();
    await pumpFor(tester, const Duration(seconds: 2));
  });

  testWidgets('flow 14b: the welcome screen', (tester) async {
    await bootApp(tester, showIntro: true);
    await shot(tester, 'R2_14_welcome');
    expect(find.byType(PageSwitcher), findsNothing);
    await AppDataService.instance.setItem(AppDataKey.introSeen, '1');
  });
}
