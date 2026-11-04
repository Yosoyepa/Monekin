import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/privacy/statement_redaction.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';
import 'package:pdfrx/pdfrx.dart';

const fixture = 'test/features_ia/fixtures/statements/';

double? fakeAmount(String input) {
  var value = input.trim().replaceAll(RegExp(r'[^0-9,\.\-+]'), '');
  if (value.contains(',')) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(value);
}

class FakeCatalog extends AiCatalog {
  const FakeCatalog() : super(accounts: const [], categories: const []);
}

class FakeInbox extends NotReadyInboxService {
  InboxDraft? draft;
  @override
  Future<String> addItem(InboxDraft value) async {
    draft = value;
    return 'item';
  }
}

class FakeClient implements AiClient {
  String? sent;
  List<AiMessage> messages = const [];
  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    this.messages = messages;
    sent = messages.last.text;
    final amounts = [
      '3200000',
      '-187450',
      '-32900',
      '-18700',
      '-56300',
      '-119900',
      '650000',
      '-23400',
      '-36000',
      '-9200',
      '-189000',
      '-14500',
    ];
    return AiResult(
      text: jsonEncode({
        'filas': [
          for (var i = 0; i < amounts.length; i++)
            {
              'fecha': '${(i + 1).toString().padLeft(2, '0')}/10/2026',
              'descripcion': 'Movimiento $i',
              'valor': amounts[i],
            },
        ],
        'saldo_inicial': '2350000',
        'saldo_final': '5512650',
      }),
    );
  }

  @override
  Future<List<String>> listModels() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final importer = StatementImporter(amountParser: fakeAmount);
  test('Nequi local CSV reconciles eight rows', () async {
    final text = await File('${fixture}nequi_2026-10.csv').readAsString();
    final result = importer.parseCsv(text, 'account')!;
    expect(result.rows.length, 8);
    expect(result.net, -175700);
    expect(result.difference, 0);
    expect(result.rows.every((row) => row.accountId == 'account'), isTrue);
  });
  test('PDF text extraction contains all transaction dates', () async {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    final text = await importer.extractPdf(
      await File('${fixture}bancolombia_ahorros_2026-10.pdf').readAsBytes(),
    );
    expect(
      RegExp(r'\b\d{2}/10/2026\b').allMatches(text).length,
      greaterThanOrEqualTo(12),
    );
    expect(text, contains('NOMINA'));
  });
  test(
    'fake AI reconciles the extracted PDF and saves an inbox draft',
    () async {
      final text = await File(
        'test/features_ia/statements/bancolombia_extracted.txt',
      ).readAsString();
      final client = FakeClient();
      final inbox = FakeInbox();
      final service = StatementImporter(
        amountParser: fakeAmount,
        catalogLoader: () async => const FakeCatalog(),
        clientLoader: () async => client,
        inbox: inbox,
      );
      final result = await service.parseWithAi(text, 'account');
      expect(client.sent, redactStatementText(text));
      expect(client.sent, isNot(contains('1234')));
      expect(client.sent, isNot(contains('Usuario de Prueba')));
      expect(client.sent, contains('Saldo inicial'));
      expect(client.sent, contains('Saldo final'));
      expect(result.rows.length, 12);
      expect(result.net, 3162650);
      expect(result.difference, 0);
      expect(
        await service.save(
          result: result,
          label: 'bancolombia-2026-10',
          text: text,
          note: 'difference: 0',
        ),
        'item',
      );
      expect(inbox.draft!.source, InboxSource.statement);
      expect(inbox.draft!.sourceRef, 'bancolombia-2026-10');
      expect(inbox.draft!.note, 'difference: 0');
    },
  );

  test(
    'F-11: the provider gets the movement lines with identifiers masked and no catalog',
    () async {
      const text = '''
Titular: JUAN PEREZ GOMEZ
Documento: CC 1.032.456.789
Cuenta de ahorros No. 12345678901
Saldo disponible: \$ 8.765.432,10
Saldo inicial: \$ 100.000,00
Fecha Descripcion Valor
01/10/2026 PAGO A 3001234567 -10.000,00
02/10/2026 COMPRA TIENDA -20.000,00
03/10/2026 ABONO NOMINA 50.000,00
Saldo final: \$ 120.000,00
''';
      final client = FakeClient();
      final service = StatementImporter(
        amountParser: fakeAmount,
        catalogLoader: () async => const FakeCatalog(),
        clientLoader: () async => client,
      );

      await service.parseWithAi(text, 'account');

      final sent = client.messages.map((m) => m.text).join('\n');
      for (final secret in [
        'JUAN',
        '1.032.456.789',
        '12345678901',
        '8.765.432',
        '3001234567',
      ]) {
        expect(sent, isNot(contains(secret)), reason: secret);
      }
      expect(sent, contains('01/10/2026 PAGO A [phone] -10.000,00'));
      expect(sent, contains(r'Saldo inicial: $ 100.000,00'));
      expect(sent, contains(r'Saldo final: $ 120.000,00'));
      expect(sent, isNot(contains('"accounts"')));
      expect(sent, isNot(contains('"categories"')));
    },
  );
}
