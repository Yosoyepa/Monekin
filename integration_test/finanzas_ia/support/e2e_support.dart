// Shared helpers of the Finanzas IA emulator E2E (T002). Owner: fi-e2e.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/layout/page_switcher.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/account/account_service.dart';
import 'package:monekin/core/database/services/app-data/app_data_service.dart';
import 'package:monekin/core/database/services/user-setting/user_setting_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/services/supported_icon/supported_icon_service.dart';
import 'package:monekin/core/utils/uuid.dart';
import 'package:monekin/main.dart' as app;

/// Fixtures pushed by the host with `adb push` (the test bundle cannot carry them).
const fixturesDir = '/data/local/tmp/e2e';

/// Receipt fixtures in the order of `test/features_ia/fixtures/EXPECTED.md`.
const receiptFixtures = <String>[
  'exito_01.jpg',
  'e2e_01_supermercado.jpg',
  'e2e_02_drogueria.jpg',
  'e2e_03_restaurante.jpg',
  'blind3_farmacia.jpg',
  'blind3_panaderia.jpg',
];

const geminiKey = String.fromEnvironment('GEMINI_TEST_API_KEY');

/// Marker lines the host script greps from the `flutter test` output.
void marker(String text) => debugPrint('E2E_MARKER $text');

/// Asks the host script (docs/e2e/run_e2e.ps1) for an `adb exec-out screencap` and waits for it.
Future<void> shot(WidgetTester tester, String name) async {
  marker('shot $name');
  await pumpFor(tester, const Duration(seconds: 2));
}

Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [finder] matches or [timeout] passes (animations never settle in this app).
Future<bool> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// Boots the real app past the onboarding with COP as the preferred currency.
Future<void> bootApp(WidgetTester tester) async {
  await AppDataService.instance.setItem(AppDataKey.introSeen, '1');
  await UserSettingService.instance.setItem(
    SettingKey.preferredCurrency,
    'COP',
  );
  await UserSettingService.instance.setItem(SettingKey.appLanguage, 'es');
  app.main();
  await pumpUntilFound(tester, find.byType(PageSwitcher));
  await pumpFor(tester, const Duration(seconds: 2));
}

/// Empties the data the flows create, so each test file starts from the same state when they all share one install.
Future<void> resetData() async {
  final db = AppDB.instance;
  for (final table in [
    'transactionTags',
    'transactionAttachments',
    'aiInboxItems',
    'transactions',
    'accounts',
  ]) {
    await db.customStatement('DELETE FROM $table');
  }
}

/// Creates the account when no account with that name exists. Returns its id.
Future<String> ensureAccount(
  String name, {
  required double iniValue,
  required DateTime date,
  int displayOrder = 10,
}) async {
  final existing = await AccountService.instance
      .getAccounts(predicate: (a, _) => a.name.equals(name))
      .first;
  if (existing.isNotEmpty) return existing.first.id;
  final id = generateUUID();
  await AccountService.instance.insertAccount(
    AccountInDB(
      id: id,
      name: name,
      iniValue: iniValue,
      displayOrder: displayOrder,
      date: date,
      type: AccountType.money,
      isSaving: false,
      trackingMode: AccountTrackingMode.transactions,
      iconId: SupportedIconService.instance.defaultSupportedIcon.id,
      currencyId: 'COP',
    ),
  );
  return id;
}

Future<bool> fixtureExists(String name) => File('$fixturesDir/$name').exists();
