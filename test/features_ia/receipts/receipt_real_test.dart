// Real-model check of the six fixture receipts against EXPECTED.md. Skipped without a Gemini test key
// (D:\Dev\secrets\gemini_test_key.txt or GEMINI_TEST_API_KEY). Model: RECEIPT_TEST_MODEL (default gemini-flash-lite-latest).
// The key is never printed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';

String? _readKey() {
  final env = Platform.environment['GEMINI_TEST_API_KEY'];
  if (env != null && env.trim().isNotEmpty) return env.trim();
  final file = File(r'D:\Dev\secrets\gemini_test_key.txt');
  if (file.existsSync()) {
    final key = file.readAsStringSync().trim();
    if (key.isNotEmpty) return key;
  }
  return null;
}

class _GeminiClient implements AiClient {
  _GeminiClient(this.key, this.model);

  final String key;
  final String model;

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final body = {
      'model': model,
      'messages': [
        for (final m in messages)
          {
            'role': m.role,
            'content': m.images.isEmpty
                ? m.text
                : [
                    {'type': 'text', 'text': m.text},
                    for (final img in m.images)
                      {
                        'type': 'image_url',
                        'image_url': {
                          'url':
                              'data:${img.mimeType};base64,${base64Encode(img.bytes)}',
                        },
                      },
                  ],
          },
      ],
      if (jsonOutput) 'response_format': {'type': 'json_object'},
    };
    final res = await http
        .post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
          ),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (res.statusCode != 200) {
      throw AiException(
        res.statusCode == 429 ? AiErrorKind.quotaExceeded : AiErrorKind.unknown,
        'HTTP ${res.statusCode}',
      );
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return AiResult(
      text: decoded['choices'][0]['message']['content'] as String,
    );
  }

  @override
  Future<List<String>> listModels() async => [];
}

class _RealCatalog extends AiCatalog {
  const _RealCatalog()
    : super(
        accounts: const [
          CatalogAccount(id: 'acc-cash', name: 'Efectivo', currency: 'COP'),
          CatalogAccount(
            id: 'acc-debit',
            name: 'Debito Bancolombia',
            currency: 'COP',
            cardLast4: ['4412'],
          ),
          CatalogAccount(id: 'acc-nequi', name: 'Nequi', currency: 'COP'),
        ],
        categories: const [
          CatalogCategory(id: 'cat-market', name: 'Mercado', type: 'E'),
          CatalogCategory(id: 'cat-health', name: 'Salud', type: 'E'),
          CatalogCategory(id: 'cat-food', name: 'Restaurantes', type: 'E'),
          CatalogCategory(id: 'cat-salary', name: 'Salario', type: 'I'),
        ],
      );

  @override
  String toPromptJson() => jsonEncode({
    'accounts': [
      for (final a in accounts)
        {'id': a.id, 'name': a.name, 'cardLast4': a.cardLast4},
    ],
    'categories': [
      for (final c in categories) {'id': c.id, 'name': c.name, 'type': c.type},
    ],
  });
}

double? _parse(String raw) => double.tryParse(
  raw
      .replaceAll(RegExp(r'[^\d,.-]'), '')
      .replaceAll('.', '')
      .replaceAll(',', '.'),
);

const _expected = <String, double>{
  'exito_01.jpg': 45900,
  'e2e_01_supermercado.jpg': 128350,
  'e2e_02_drogueria.jpg': 45900,
  'e2e_03_restaurante.jpg': 1234567,
  'blind3_farmacia.jpg': 67300,
  'blind3_panaderia.jpg': 18500,
};

void main() {
  final key = _readKey();
  final model =
      Platform.environment['RECEIPT_TEST_MODEL'] ?? 'gemini-flash-lite-latest';

  test(
    'six fixture receipts read with $model',
    () async {
      final analyzer = ReceiptAnalyzer(
        clientProvider: () async => _GeminiClient(key!, model),
        catalogLoader: () async => const _RealCatalog(),
        cardMapLoader: () async => {'4412': 'acc-debit'},
        accountForLast4: (last4) async => last4 == '4412' ? 'acc-debit' : null,
        parseAmount: _parse,
      );

      final rows = <String>[];
      var exact = 0;
      for (final entry in _expected.entries) {
        final file = File('test/features_ia/fixtures/receipts/${entry.key}');
        final draft = await analyzer.analyze(
          imageBytes: await file.readAsBytes(),
          filePath: file.path,
          fileName: entry.key,
        );
        final read = draft.proposals.isEmpty
            ? null
            : draft.proposals.single.amount;
        final ok = read == entry.value;
        if (ok) exact++;
        final p = draft.proposals.isEmpty ? null : draft.proposals.single;
        rows.add(
          '| ${entry.key} | ${entry.value.toStringAsFixed(0)} | ${read?.toStringAsFixed(0) ?? draft.note} | ${ok ? 'OK' : 'FAIL'} | ${p?.title} | ${p?.date.toIso8601String().substring(0, 10)} | ${p?.categoryId} | ${p?.accountId} |',
        );
      }
      // ignore: avoid_print
      print(
        '\nModel: $model\n| File | Expected | Read | Result | Merchant | Date | Category | Account |\n|---|---|---|---|---|---|---|---|\n${rows.join('\n')}\nExact totals: $exact/${_expected.length}',
      );
      expect(exact, _expected.length);
    },
    skip: key == null ? 'No Gemini test key' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
