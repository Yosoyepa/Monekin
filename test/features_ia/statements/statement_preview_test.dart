// Statements (T002, round 3): the user sees the exact text before it is sent, and cancelling sends nothing.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/consent/ai_consent_sheet.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/statements/statement_import_page.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../notifications/test_support.dart';
import '../utils/consent_support.dart';

class _Catalog extends AiCatalog {
  const _Catalog()
    : super(
        accounts: const [
          CatalogAccount(id: 'acc-1', name: 'Cuenta', currency: 'COP'),
        ],
        categories: const [
          CatalogCategory(id: 'cat-food', name: 'Food', type: 'E'),
        ],
      );
}

/// An inbox that refuses the item, so the page stays where it is after the import.
class _RefusingInbox extends NotReadyInboxService {}

const _statement = '''
EXTRACTO DE CUENTA
Titular: Maria Fernanda Lopez   Documento 1020304050
Cuenta de ahorros 1234567890  correo maria@example.com  tel 3001234567
Fecha Descripcion Valor
01/11/2026 EXITO -45.900
02/11/2026 NOMINA 3.000.000
Saldo inicial 100.000
Saldo final 3.054.100
''';

const _answer =
    '{"filas":[{"fecha":"01/11/2026","descripcion":"EXITO","valor":"-45.900"},'
    '{"fecha":"02/11/2026","descripcion":"NOMINA","valor":"3.000.000"}],'
    '"saldo_inicial":"100.000","saldo_final":"3.054.100","rows":[]}';

void main() {
  late RecordingAiClient client;
  late StatementImporter importer;

  setUp(() {
    client = RecordingAiClient(_answer);
    AiService.debugClientOverride = client;
    importer = StatementImporter(
      catalogLoader: () async => const _Catalog(),
      inbox: _RefusingInbox(),
    );
    debugStatementFileOverride = () async => PlatformFile(
      name: 'extracto.txt',
      size: _statement.length,
      bytes: Uint8List.fromList(_statement.codeUnits),
    );
  });

  tearDown(() {
    AiService.debugClientOverride = null;
    debugStatementFileOverride = null;
  });

  Future<void> pumpAndImport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(ChanchiMascot.preload);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(home: StatementImportPage(importer: importer)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('statement-choose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuenta').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('statement-import')));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet shows exactly the text the provider receives', (
    tester,
  ) async {
    await useTestConsent(grantAll: false);
    await pumpAndImport(tester);

    // First use: the consent sheet comes before anything else.
    expect(find.byType(AiConsentSheet), findsOneWidget);
    expect(client.requests, isEmpty);
    await tester.tap(find.byKey(const Key('consent-accept')));
    await tester.pumpAndSettle();

    expect(find.byType(AiPreviewSheet), findsOneWidget);
    expect(client.requests, isEmpty);
    final shown = tester
        .widget<SelectableText>(find.byKey(const Key('preview-text')))
        .data!;
    expect(shown, isNot(contains('1234567890')));
    expect(shown, isNot(contains('maria@example.com')));
    expect(shown, isNot(contains('3001234567')));
    expect(shown, contains('EXITO'));

    await tester.tap(find.byKey(const Key('preview-send')));
    await tester.pumpAndSettle();

    final statementCalls = [
      for (final request in client.requests)
        if (request.first.text.startsWith('Extrae todas')) request.last.text,
    ];
    expect(statementCalls, [shown]);
  });

  testWidgets('cancelling the preview makes no request', (tester) async {
    await useTestConsent();
    await pumpAndImport(tester);

    expect(find.byType(AiPreviewSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('preview-cancel')));
    await tester.pumpAndSettle();

    expect(client.requests, isEmpty);
    expect(find.byType(AiPreviewSheet), findsNothing);
  });

  testWidgets('«No usar IA aquí» keeps a statement that needs the AI unread', (
    tester,
  ) async {
    await useTestConsent(grantAll: false);
    await pumpAndImport(tester);

    await tester.tap(find.byKey(const Key('consent-decline')));
    await tester.pumpAndSettle();

    final t = Translations.of(tester.element(find.byType(StatementImportPage)));
    expect(find.text(t.ia_statements.ai_needed), findsOneWidget);
    expect(client.requests, isEmpty);
  });

  test('the retry for reconciliation sends the approved text again', () async {
    await useTestConsent();
    // Rows that do not match the balances: the importer asks once more.
    client.answer =
        '{"filas":[{"fecha":"01/11/2026","descripcion":"EXITO","valor":"-45.900"}],'
        '"saldo_inicial":"100.000","saldo_final":"3.054.100"}';
    final approved = importer.textToSend(_statement);

    await importer.parseWithAi(_statement, 'acc-1', approvedText: approved);

    expect(client.requests, hasLength(2));
    expect(client.requests[0].last.text, approved);
    expect(client.requests[1].last.text, approved);
    expect(client.requests[1].first.text, contains('no cuadró'));
  });

  test('the net and the difference are saved as data of the item', () async {
    final inbox = FakeInbox();
    final saving = StatementImporter(inbox: inbox);
    final result = StatementResult(
      [
        ProposedTransaction(
          date: DateTime(2026, 11, 2),
          title: 'NOMINA',
          amount: 3000000,
          type: TransactionType.income,
        ),
        ProposedTransaction(
          date: DateTime(2026, 11, 1),
          title: 'EXITO',
          amount: 45900,
        ),
      ],
      100000,
      3054000,
    );

    await saving.save(
      result: result,
      label: 'nov',
      text: _statement,
      note: 'free text without figures',
    );

    final data = inbox.drafts.single.data!;
    expect(data[InboxDataKeys.net], 2954100);
    expect(data[InboxDataKeys.difference], closeTo(100, 0.001));
  });
}
