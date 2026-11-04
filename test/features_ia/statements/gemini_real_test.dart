import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';

import '../utils/real_ai.dart';

class _Catalog extends AiCatalog {
  const _Catalog() : super(accounts: const [], categories: const []);
}

const _nequiCatalog = AiCatalog(
  accounts: [CatalogAccount(id: 'nequi', name: 'Nequi', currency: 'COP')],
  categories: [
    CatalogCategory(id: 'food', name: 'Comida', type: 'E'),
    CatalogCategory(id: 'transport', name: 'Transporte', type: 'E'),
    CatalogCategory(id: 'subscriptions', name: 'Suscripciones', type: 'E'),
    CatalogCategory(id: 'cash', name: 'Efectivo', type: 'E'),
    CatalogCategory(id: 'transfers', name: 'Transferencias', type: 'B'),
    CatalogCategory(id: 'income', name: 'Ingresos', type: 'I'),
  ],
);

class _Gemini implements AiClient {
  _Gemini(this.key);
  final String key;
  int calls = 0;
  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls++;
    final response = await http
        .post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
          ),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'gemini-flash-lite-latest',
            'messages': [
              for (final message in messages)
                {'role': message.role, 'content': message.text},
            ],
            'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw StateError('Gemini HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>;
    return AiResult(text: (choices.first['message']['content'] as String));
  }

  @override
  Future<List<String>> listModels() async => [];
}

double? _amount(String raw) {
  var value = raw.replaceAll(RegExp(r'[^0-9,.+\-]'), '');
  if (value.contains(',')) {
    if (value.lastIndexOf(',') > value.lastIndexOf('.')) {
      value = value.replaceAll('.', '').replaceAll(',', '.');
    } else {
      value = value.replaceAll(',', '');
    }
  } else if (RegExp(r'^[-+]?\d{1,3}(\.\d{3})+$').hasMatch(value)) {
    value = value.replaceAll('.', '');
  }
  return double.tryParse(value);
}

void main() {
  final key = geminiTestKey();
  test(
    'real Gemini reconciles extracted PDF',
    () async {
      final text = await File(
        'test/features_ia/statements/bancolombia_extracted.txt',
      ).readAsString();
      final importer = StatementImporter(
        amountParser: _amount,
        catalogLoader: () async => const _Catalog(),
        clientLoader: () async => _Gemini(key!),
      );
      final result = await importer.parseWithAi(text, 'account');
      expect(result.rows.length, 12);
      expect(result.net, 3162650);
      expect(result.difference, 0);
    },
    skip: realAiSkip(),
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'real Gemini proposes categories for the Nequi CSV rows',
    () async {
      final text = await File(
        'test/features_ia/fixtures/statements/nequi_2026-10.csv',
      ).readAsString();
      final client = _Gemini(key!);
      final importer = StatementImporter(
        catalogLoader: () async => _nequiCatalog,
        clientLoader: () async => client,
      );

      final result = await importer.proposeCategories(
        importer.parseCsv(text, 'nequi')!,
      );

      final names = {for (final c in _nequiCatalog.categories) c.id: c.name};
      for (final row in result.rows) {
        debugPrint(
          '${row.title} | ${row.type.name} | ${names[row.categoryId] ?? 'sin categoría'}',
        );
      }
      final categorized = result.rows.where((row) => row.categoryId != null);
      debugPrint(
        'categorized ${categorized.length} of ${result.rows.length} rows in ${client.calls} call(s)',
      );
      expect(client.calls, lessThanOrEqualTo(3));
      expect(result.categoryWarning, isFalse);
    },
    skip: realAiSkip(),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
