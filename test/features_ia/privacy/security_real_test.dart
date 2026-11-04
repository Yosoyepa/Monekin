// Real Gemini check of the minimal prompts: 4 calls. Runs only with RUN_REAL_AI_TESTS=1 and a key
// (D:\Dev\secrets\gemini_test_key.txt or GEMINI_TEST_API_KEY). The key is never printed. Uses the production client, so max_tokens travels on the wire too.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/core/ai/openai_compatible_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/core/privacy/statement_redaction.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';

import '../utils/real_ai.dart';

class _Counting implements AiClient, AiCappedClient {
  _Counting(this.inner);
  final OpenAiCompatibleClient inner;
  final tokens = <int>[];

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) => chatCapped(messages, maxTokens: null);

  @override
  Future<AiResult> chatCapped(
    List<AiMessage> messages, {
    required int? maxTokens,
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final result = await inner.chatCapped(
      messages,
      maxTokens: maxTokens,
      jsonOutput: jsonOutput,
      timeout: timeout,
    );
    tokens.add(result.completionTokens ?? -1);
    return result;
  }

  @override
  Future<List<String>> listModels() async => [];
}

const _catalog = AiCatalog(
  accounts: [
    CatalogAccount(
      id: 'acc-debit',
      name: 'Debito Bancolombia',
      currency: 'COP',
    ),
    CatalogAccount(id: 'acc-cash', name: 'Efectivo', currency: 'COP'),
  ],
  categories: [
    CatalogCategory(id: 'cat-market', name: 'Mercado', type: 'E'),
    CatalogCategory(id: 'cat-health', name: 'Salud', type: 'E'),
    CatalogCategory(id: 'cat-salary', name: 'Salario', type: 'I'),
  ],
);

void main() {
  final key = geminiTestKey();
  final skip = realAiSkip();
  late _Counting client;

  setUp(() {
    final gemini = aiPresets[AiProviderId.gemini]!;
    client = _Counting(
      OpenAiCompatibleClient(
        baseUrl: gemini.baseUrl,
        apiKey: key ?? '',
        model: gemini.model,
      ),
    );
  });

  Future<(double?, String?)> receipt(String file) async {
    final path = 'test/features_ia/fixtures/receipts/$file';
    final draft =
        await ReceiptAnalyzer(
          clientProvider: () async => client,
          catalogLoader: () async => _catalog,
          accountForLast4: (last4) async =>
              last4 == '4412' ? 'acc-debit' : null,
        ).analyze(
          imageBytes: await File(path).readAsBytes(),
          filePath: path,
          fileName: file,
        );
    final proposal = draft.proposals.singleOrNull;
    return (proposal?.amount, proposal?.accountId);
  }

  test(
    'receipt exito_01 keeps its exact total',
    () async {
      final (amount, _) = await receipt('exito_01.jpg');
      // ignore: avoid_print
      print('exito_01: $amount, answer tokens ${client.tokens}');
      expect(amount, 45900);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'receipt e2e_02_drogueria keeps its total and its card becomes the account locally',
    () async {
      final (amount, account) = await receipt('e2e_02_drogueria.jpg');
      // ignore: avoid_print
      print(
        'e2e_02_drogueria: $amount, account $account, answer tokens ${client.tokens}',
      );
      expect(amount, 45900);
      expect(account, 'acc-debit');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Nequi reconciles with difference 0 on the masked text',
    () async {
      final text = File(
        'test/features_ia/fixtures/statements/nequi_2026-10.csv',
      ).readAsStringSync();
      final masked = redactStatementText(text);
      final result = await StatementImporter(
        amountParser: parseLocalizedAmount,
        clientLoader: () async => client,
      ).parseWithAi(text, 'acc-nequi');
      // ignore: avoid_print
      print(
        'Nequi: ${masked.split('\n').length} lines sent of ${text.split('\n').length}, ${result.rows.length} rows, net ${result.net}, difference ${result.difference}, answer tokens ${client.tokens}',
      );
      expect(result.rows.length, 8);
      expect(result.net, -175700);
      expect(result.difference, 0);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Bancolombia reconciles with difference 0 on the masked text',
    () async {
      final text = File(
        'test/features_ia/statements/bancolombia_extracted.txt',
      ).readAsStringSync();
      final masked = redactStatementText(text);
      final result = await StatementImporter(
        amountParser: parseLocalizedAmount,
        clientLoader: () async => client,
      ).parseWithAi(text, 'acc-debit');
      // ignore: avoid_print
      print(
        'Bancolombia: ${masked.split('\n').length} lines sent of ${text.split('\n').length}, ${result.rows.length} rows, net ${result.net}, difference ${result.difference}, answer tokens ${client.tokens}',
      );
      expect(result.rows.length, 12);
      expect(result.net, 3162650);
      expect(result.difference, 0);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
