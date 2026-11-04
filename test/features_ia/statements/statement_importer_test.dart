import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
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
  @override
  String toPromptJson() => '{"accounts":[],"categories":[]}';
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
  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
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
      expect(client.sent, text);
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
}
