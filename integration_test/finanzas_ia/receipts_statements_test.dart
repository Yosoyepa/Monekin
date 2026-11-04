// Flows 3 and 4 of the Finanzas IA emulator E2E (T002): receipts and statements with the real Gemini.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/core/utils/unique_app_widgets_keys.dart';
import 'package:monekin/features_ia/core/cards/card_map.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/settings/ai_settings_page.dart';
import 'package:monekin/features_ia/receipts/receipt_capture.dart';
import 'package:monekin/features_ia/statements/statement_import_page.dart';

import 'support/e2e_support.dart';

/// Expected totals of `test/features_ia/fixtures/EXPECTED.md`.
const expectedTotals = <String, double>{
  'exito_01.jpg': 45900,
  'e2e_01_supermercado.jpg': 128350,
  'e2e_02_drogueria.jpg': 45900,
  'e2e_03_restaurante.jpg': 1234567,
  'blind3_farmacia.jpg': 67300,
  'blind3_panaderia.jpg': 18500,
};

Future<List<Map<String, Object?>>> query(String sql) async {
  final rows = await AppDB.instance.customSelect(sql).get();
  return [for (final r in rows) r.data];
}

void goHome() => navigatorKey.currentState?.popUntil((route) => route.isFirst);

/// Picks the account/category of every review row that still asks for one, then taps Confirm.
Future<void> completeReviewAndConfirm(
  WidgetTester tester, {
  required String accountName,
  required String shotPrefix,
  bool expectProcessed = true,
}) async {
  for (var index = 0; index < 20; index++) {
    final accountTile = find.byKey(Key('inbox-account-$index'));
    final categoryTile = find.byKey(Key('inbox-category-$index'));
    if (accountTile.evaluate().isEmpty) {
      // Rows are built lazily below the long original-text block.
      try {
        await tester.scrollUntilVisible(
          accountTile,
          400,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 40,
        );
      } catch (_) {
        break;
      }
    }
    await tester.ensureVisible(accountTile);
    if (find
        .descendant(of: accountTile, matching: find.textContaining('Elige'))
        .evaluate()
        .isNotEmpty) {
      await tester.tap(accountTile);
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.text(accountName).last);
      await pumpFor(tester, const Duration(seconds: 1));
    }
    await tester.ensureVisible(categoryTile);
    if (find
        .descendant(of: categoryTile, matching: find.textContaining('Elige'))
        .evaluate()
        .isNotEmpty) {
      await Scrollable.ensureVisible(
        tester.element(categoryTile),
        alignment: 0.5,
      );
      await pumpFor(tester, const Duration(milliseconds: 500));
      await tester.tap(categoryTile);
      await pumpFor(tester, const Duration(seconds: 1));
      if (index == 0) await shot(tester, '${shotPrefix}_category_picker');
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpFor(tester, const Duration(seconds: 2));
      final others = find.text('Others').hitTestable();
      if (others.evaluate().isEmpty) {
        await shot(tester, '${shotPrefix}_picker_failed_$index');
        fail('category picker of row $index has no tappable "Others"');
      }
      // The label alone is not tappable: hit the icon circle above it.
      await tester.tapAt(tester.getCenter(others.first) - const Offset(0, 40));
      await pumpFor(tester, const Duration(milliseconds: 800));
      await tester.tap(find.text('Guardar').hitTestable().first);
      await pumpFor(tester, const Duration(seconds: 1));
      final stillAsking = find
          .descendant(of: categoryTile, matching: find.textContaining('Elige'))
          .evaluate()
          .isNotEmpty;
      marker('row $index category picked, still asking=$stillAsking');
      if (stillAsking) await shot(tester, '${shotPrefix}_row_${index}_unset');
    }
  }
  await shot(tester, '${shotPrefix}_review');
  final confirm = find.widgetWithText(FilledButton, 'Confirmar');
  await tester.ensureVisible(confirm);
  await tester.tap(confirm);
  await pumpFor(tester, const Duration(milliseconds: 600));
  final celebration = find.byKey(const Key('inbox-celebration'));
  marker(
    '$shotPrefix celebration visible=${celebration.evaluate().isNotEmpty}',
  );
  await shot(tester, '${shotPrefix}_confirmed');
  // The redesigned review closes itself once everything is saved; the callers check the base.
  var left = false;
  for (var i = 0; i < 40 && !left; i++) {
    await pumpFor(tester, const Duration(milliseconds: 500));
    left = find.text('Revisar transacciones').evaluate().isEmpty;
  }
  marker('$shotPrefix review page closed=$left');
  if (expectProcessed) {
    expect(left, isTrue, reason: 'review page did not close after Confirm');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flow 3: six receipts -> review -> confirm', (tester) async {
    await bootApp(tester);
    await resetData();
    await ensureAiConfigured();
    await resetConsent();
    final bank = await ensureAccount(
      'Bancolombia Ahorros',
      iniValue: 2350000,
      date: DateTime(2026, 1, 1),
    );
    await ensureAccount(
      'Efectivo',
      iniValue: 500000,
      date: DateTime(2026, 1, 1),
    );
    await CardMapService.instance.save({'9911': bank});

    final failures = <String>[];
    for (final name in receiptFixtures) {
      try {
        expect(await fixtureExists(name), isTrue, reason: 'fixture $name');
        debugReceiptPhotosOverride = () async => [XFile('$fixturesDir/$name')];
        final before =
            (await query('SELECT COUNT(*) AS n FROM transactions')).first['n']
                as int;
        unawaited(startReceiptCapture(navigatorKey.currentContext!));
        // The first receipt asks to allow the function; the answer is kept for the rest.
        if (name == receiptFixtures.first) {
          await acceptConsent(tester, shotName: 'R2_03_consent_receipt');
        }
        final reached = await pumpUntilFound(
          tester,
          find.byKey(const Key('inbox-account-0')),
          timeout: const Duration(seconds: 90),
        );
        expect(reached, isTrue, reason: 'review page not reached for $name');
        final shotName = name.replaceAll('.jpg', '');
        await completeReviewAndConfirm(
          tester,
          accountName: 'Efectivo',
          shotPrefix: '03_receipt_$shotName',
        );
        final after =
            (await query('SELECT COUNT(*) AS n FROM transactions')).first['n']
                as int;
        expect(after, before + 1, reason: 'one transaction expected for $name');
        marker('result receipt $name created');
      } catch (e) {
        failures.add('$name: $e');
        marker('result receipt $name FAILED');
      } finally {
        goHome();
        await pumpFor(tester, const Duration(seconds: 1));
      }
    }
    debugReceiptPhotosOverride = null;

    final rows = await query('''
      SELECT t.value AS value, a.name AS account, t.notes AS notes,
             (SELECT COUNT(*) FROM transactionTags tt JOIN tags g ON g.id = tt.tagID
               WHERE tt.transactionID = t.id AND g.name = 'ia') AS ia,
             (SELECT COUNT(*) FROM transactionAttachments x WHERE x.transactionID = t.id) AS photos
      FROM transactions t JOIN accounts a ON a.id = t.accountID
      WHERE t.notes LIKE '%[origen: recibo:%'
      ORDER BY t.date''');
    for (final r in rows) {
      marker(
        'row ${r['value']} | ${r['account']} | ia=${r['ia']} | photos=${r['photos']} | ${r['notes']}'
            .replaceAll('\n', ' '),
      );
    }
    expect(rows.length, 6, reason: 'receipt transactions in the base');
    for (final r in rows) {
      expect(r['ia'], 1, reason: 'tag ia on ${r['value']}');
      expect(r['photos'], 1, reason: 'photo attached to ${r['value']}');
    }
    final values = [for (final r in rows) (r['value'] as num).toDouble().abs()]
      ..sort();
    final expected = expectedTotals.values.toList()..sort();
    expect(values, expected, reason: 'amounts vs EXPECTED.md');
    expect(failures, isEmpty);
  });

  testWidgets('flow 4: Nequi CSV and Bancolombia PDF, reconciliation and re-import', (
    tester,
  ) async {
    await bootApp(tester);
    await resetData();
    await ensureAiConfigured();
    await resetConsent();
    await ensureAccount('Nequi', iniValue: 350000, date: DateTime(2026, 1, 1));
    await ensureAccount(
      'Bancolombia Ahorros',
      iniValue: 2350000,
      date: DateTime(2026, 1, 1),
    );

    Future<void> importStatement(
      String file,
      String account,
      String prefix, {
      required bool confirm,
    }) async {
      final bytes = await File('$fixturesDir/$file').readAsBytes();
      debugStatementFileOverride = () async => PlatformFile(
        name: file,
        size: bytes.length,
        bytes: bytes,
        path: '$fixturesDir/$file',
      );
      unawaited(RouteUtils.pushRoute(const StatementImportPage()));
      expect(
        await pumpUntilFound(tester, find.textContaining('Elegir CSV')),
        isTrue,
      );
      await tester.tap(find.textContaining('Elegir CSV'));
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.text(account).last);
      await pumpFor(tester, const Duration(seconds: 1));
      await shot(tester, '${prefix}_form');
      await tester.tap(find.widgetWithText(FilledButton, 'Importar y revisar'));
      // The statement function asks once; every send then shows the exact text first.
      if (await consentSheetShown(
        tester,
        timeout: const Duration(seconds: 6),
      )) {
        await acceptConsent(tester, shotName: '${prefix}_consent');
      }
      final sent = await answerPreview(
        tester,
        send: true,
        shotName: '${prefix}_preview',
      );
      marker(
        'preview of $file: ${sent.length} chars, first line "${sent.split('\n').first}"',
      );
      final reached = await pumpUntilFound(
        tester,
        find.text('Revisar transacciones'),
        timeout: const Duration(seconds: 120),
      );
      if (!reached) {
        final snack = find.byType(SnackBar);
        marker(
          'import failed for $file; snackbar=${snack.evaluate().isEmpty ? 'none' : (find.descendant(of: snack, matching: find.byType(Text)).evaluate().first.widget as Text).data}',
        );
        await shot(tester, '${prefix}_import_failed');
      }
      expect(reached, isTrue, reason: 'review page not reached for $file');
      final difference = find.text('Cuadra con los saldos del extracto.');
      marker(
        'reconciliation $file visible=${find.text('Conciliación').evaluate().isNotEmpty} balanced=${difference.evaluate().isNotEmpty}',
      );
      expect(
        difference,
        findsOneWidget,
        reason: 'reconciliation card of $file does not balance',
      );
      if (confirm) {
        await completeReviewAndConfirm(
          tester,
          accountName: account,
          shotPrefix: prefix,
        );
      } else {
        await shot(tester, '${prefix}_review');
      }
    }

    await importStatement(
      'nequi_2026-10.csv',
      'Nequi',
      '04_nequi',
      confirm: true,
    );
    goHome();
    await pumpFor(tester, const Duration(seconds: 1));
    final nequi = await query(
      "SELECT COUNT(*) AS n FROM transactions t JOIN accounts a ON a.id=t.accountID WHERE a.name='Nequi' AND t.notes LIKE '%[origen: extracto:%'",
    );
    marker('nequi created ${nequi.first['n']}');
    expect(nequi.first['n'], 8);

    await importStatement(
      'bancolombia_ahorros_2026-10.pdf',
      'Bancolombia Ahorros',
      '04_bancolombia',
      confirm: true,
    );
    goHome();
    await pumpFor(tester, const Duration(seconds: 1));
    final bc = await query(
      "SELECT COUNT(*) AS n FROM transactions t JOIN accounts a ON a.id=t.accountID WHERE a.name='Bancolombia Ahorros' AND t.notes LIKE '%[origen: extracto:%'",
    );
    marker('bancolombia created ${bc.first['n']}');
    expect(bc.first['n'], 12);

    // Re-import: rows marked as duplicates, nothing created unless forced.
    await importStatement(
      'nequi_2026-10.csv',
      'Nequi',
      '04_nequi_reimport',
      confirm: false,
    );
    var flagged = find.textContaining('duplicado').evaluate().isNotEmpty;
    if (!flagged) {
      try {
        await tester.scrollUntilVisible(
          find.textContaining('duplicado'),
          400,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 40,
        );
        flagged = true;
      } catch (_) {}
    }
    marker('reimport duplicate warning visible=$flagged');
    await shot(tester, '04_nequi_reimport_duplicates');
    // Back to the top, fill the categories so Confirm is possible, and confirm without forcing.
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 20000),
      20000,
    );
    await pumpFor(tester, const Duration(seconds: 1));
    await completeReviewAndConfirm(
      tester,
      accountName: 'Nequi',
      shotPrefix: '04_nequi_reimport',
      expectProcessed: false,
    );
    final again = await query(
      "SELECT COUNT(*) AS n FROM transactions t JOIN accounts a ON a.id=t.accountID WHERE a.name='Nequi' AND t.notes LIKE '%[origen: extracto:%'",
    );
    marker('nequi after reimport ${again.first['n']}');
    expect(again.first['n'], 8, reason: 're-import must create 0');
    goHome();
  });

  testWidgets('flow 3b: declining the consent sends nothing', (tester) async {
    await bootApp(tester);
    await resetData();
    await ensureAiConfigured();
    await resetConsent();
    final counting = await CountingAiClient.install();
    addTearDown(CountingAiClient.uninstall);
    var pickerCalls = 0;
    debugReceiptPhotosOverride = () async {
      pickerCalls++;
      return [XFile('$fixturesDir/${receiptFixtures[1]}')];
    };
    addTearDown(() => debugReceiptPhotosOverride = null);

    unawaited(startReceiptCapture(navigatorKey.currentContext!));
    await declineConsent(tester, shotName: 'R2_03b_consent_declined');
    await pumpFor(tester, const Duration(seconds: 3));
    final items = await query('SELECT COUNT(*) AS n FROM aiInboxItems');
    final config = await currentAiConfig();
    final granted = await AiConsent.instance.isGranted(
      AiFeature.receipt,
      config,
    );
    marker(
      'declined: ai calls=${counting.calls} photo picker calls=$pickerCalls inbox items=${items.first['n']} granted=$granted',
    );
    await shot(tester, 'R2_03b_after_decline');
    expect(counting.calls, 0, reason: 'a declined consent still called the AI');
    expect(pickerCalls, 0, reason: 'the photo was taken before the consent');
    expect(items.first['n'], 0);
    expect(granted, isFalse);

    // The settings page shows the function as off; once accepted it can be turned off again there.
    unawaited(startReceiptCapture(navigatorKey.currentContext!));
    await acceptConsent(tester);
    expect(
      await pumpUntilFound(
        tester,
        find.byKey(const Key('inbox-account-0')),
        timeout: const Duration(seconds: 90),
      ),
      isTrue,
    );
    marker('accepted: ai calls=${counting.calls}');
    expect(counting.calls, greaterThanOrEqualTo(1));
    goHome();
    await pumpFor(tester, const Duration(seconds: 1));
    unawaited(RouteUtils.pushRoute(const AiSettingsPage()));
    expect(
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('ai-consent-receipt')),
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-consent-receipt')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await shot(tester, 'R2_03b_settings_consent_on');
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('ai-consent-receipt')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('ai-consent-receipt')));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(
      await AiConsent.instance.isGranted(AiFeature.receipt, config),
      isFalse,
    );
    await shot(tester, 'R2_03b_settings_consent_off');
  });

  testWidgets(
    'flow 11: statement preview, cancel sends nothing and send reconciles',
    (tester) async {
      await bootApp(tester);
      await resetData();
      await ensureAiConfigured();
      await resetConsent();
      await ensureAccount(
        'Nequi',
        iniValue: 350000,
        date: DateTime(2026, 1, 1),
      );
      final counting = await CountingAiClient.install();
      addTearDown(CountingAiClient.uninstall);
      final bytes = await File('$fixturesDir/nequi_2026-10.csv').readAsBytes();
      debugStatementFileOverride = () async => PlatformFile(
        name: 'nequi_2026-10.csv',
        size: bytes.length,
        bytes: bytes,
        path: '$fixturesDir/nequi_2026-10.csv',
      );
      addTearDown(() => debugStatementFileOverride = null);

      Future<void> fillAndImport() async {
        unawaited(RouteUtils.pushRoute(const StatementImportPage()));
        expect(
          await pumpUntilFound(tester, find.textContaining('Elegir CSV')),
          isTrue,
        );
        await tester.tap(find.textContaining('Elegir CSV'));
        await pumpFor(tester, const Duration(seconds: 1));
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await pumpFor(tester, const Duration(seconds: 1));
        await tester.tap(find.text('Nequi').last);
        await pumpFor(tester, const Duration(seconds: 1));
        await tester.tap(
          find.widgetWithText(FilledButton, 'Importar y revisar'),
        );
      }

      // Cancel at the preview: the review opens with the rows read on the phone, and nothing was sent.
      await fillAndImport();
      await acceptConsent(tester, shotName: 'R2_11_consent_statement');
      final cancelledText = await answerPreview(
        tester,
        send: false,
        shotName: 'R2_11_preview_cancel',
      );
      marker('cancelled preview had ${cancelledText.length} chars');
      expect(
        await pumpUntilFound(
          tester,
          find.text('Revisar transacciones'),
          timeout: const Duration(seconds: 60),
        ),
        isTrue,
        reason: 'cancelling the preview must still open the local review',
      );
      await pumpFor(tester, const Duration(seconds: 2));
      marker('after cancel: ai calls=${counting.calls}');
      await shot(tester, 'R2_11_review_without_ai');
      expect(
        counting.calls,
        0,
        reason: 'cancelling the preview still called the AI',
      );
      goHome();
      await pumpFor(tester, const Duration(seconds: 1));

      // Send: the AI is called once for the categories and the statement reconciles.
      await fillAndImport();
      final sentText = await answerPreview(
        tester,
        send: true,
        shotName: 'R2_11_preview_send',
      );
      marker('sent preview had ${sentText.length} chars');
      expect(
        await pumpUntilFound(
          tester,
          find.text('Revisar transacciones'),
          timeout: const Duration(seconds: 120),
        ),
        isTrue,
      );
      marker('after send: ai calls=${counting.calls}');
      expect(counting.calls, greaterThanOrEqualTo(1));
      final difference = find.text('Cuadra con los saldos del extracto.');
      marker('reconciliation balanced=${difference.evaluate().isNotEmpty}');
      await shot(tester, 'R2_11_reconciliation');
      expect(difference, findsOneWidget);
      await completeReviewAndConfirm(
        tester,
        accountName: 'Nequi',
        shotPrefix: 'R2_11_nequi',
      );
      final created = await query(
        "SELECT COUNT(*) AS n FROM transactions t JOIN accounts a ON a.id=t.accountID WHERE a.name='Nequi' AND t.notes LIKE '%[origen: extracto:%'",
      );
      marker('nequi created ${created.first['n']}');
      expect(created.first['n'], 8);
    },
  );
}
