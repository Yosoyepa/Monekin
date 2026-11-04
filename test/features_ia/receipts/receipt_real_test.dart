// Real-model check of the six fixture receipts against EXPECTED.md. Skipped without a Gemini test key
// (D:\Dev\secrets\gemini_test_key.txt or GEMINI_TEST_API_KEY). Model: RECEIPT_TEST_MODEL (default gemini-flash-lite-latest).
// The key is never printed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/core/ai/openai_compatible_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';

import '../utils/real_ai.dart';

/// The production client against Gemini, recording how many answer tokens each call used.
class _RecordingClient implements AiClient, AiCappedClient {
  _RecordingClient(String key, String model)
    : _inner = OpenAiCompatibleClient(
        baseUrl: aiPresets[AiProviderId.gemini]!.baseUrl,
        apiKey: key,
        model: model,
      );

  final OpenAiCompatibleClient _inner;
  final completionTokens = <int>[];
  var calls = 0;

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) => chatCapped(
    messages,
    maxTokens: null,
    jsonOutput: jsonOutput,
    timeout: timeout,
  );

  @override
  Future<AiResult> chatCapped(
    List<AiMessage> messages, {
    required int? maxTokens,
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls++;
    final result = await _inner.chatCapped(
      messages,
      maxTokens: maxTokens,
      jsonOutput: jsonOutput,
      timeout: timeout,
    );
    completionTokens.add(result.completionTokens ?? -1);
    return result;
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
  final key = geminiTestKey();
  final model =
      Platform.environment['RECEIPT_TEST_MODEL'] ?? 'gemini-flash-lite-latest';

  test(
    'six fixture receipts read with $model',
    () async {
      final client = _RecordingClient(key!, model);
      final analyzer = ReceiptAnalyzer(
        clientProvider: () async => client,
        catalogLoader: () async => const _RealCatalog(),
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
        '\nModel: $model (${client.calls} calls, answer tokens ${client.completionTokens})\n| File | Expected | Read | Result | Merchant | Date | Category | Account |\n|---|---|---|---|---|---|---|---|\n${rows.join('\n')}\nExact totals: $exact/${_expected.length}',
      );
      expect(exact, _expected.length);
    },
    skip: realAiSkip(),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
