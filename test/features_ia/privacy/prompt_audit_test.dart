// F-01 audit: every request the AI features of this app build, with fixtures that hold accounts, cards, CC and balances,
// carries none of them. The client is a fake that captures each request as the provider would receive it.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_service_impl.dart';
import 'package:monekin/features_ia/insights/recategorize_service.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';

import '../utils/consent_support.dart';
import 'jpeg_fixture.dart';

/// What must never reach the provider.
const _forbidden = <String>[
  // Account names and ids
  'Cuenta Nomina Bancolombia',
  'Ahorros Davivienda Personal',
  'acc-nomina',
  'acc-davivienda',
  // Card last 4
  '4412',
  '9911',
  // Documents, holder, contact
  '1032456789',
  '1.032.456.789',
  '900.123.456',
  'JUAN PEREZ',
  'juan.perez@example.com',
  '3001234567',
  '300 123 4567',
  // Account numbers and balances
  '12345678901',
  '8.765.432',
  '8765432',
  '2.500.000',
];

class _Request {
  _Request(this.messages, this.maxTokens);
  final List<AiMessage> messages;
  final int? maxTokens;

  String get text => [
    for (final m in messages) ...[m.role, m.text],
  ].join('\n');
}

class _CapturingClient implements AiClient, AiCappedClient {
  _CapturingClient(this.answer);

  final String Function(_Request request) answer;
  final requests = <_Request>[];

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
    final request = _Request(messages, maxTokens);
    requests.add(request);
    return AiResult(text: answer(request));
  }

  @override
  Future<List<String>> listModels() async => const [];
}

const _catalog = AiCatalog(
  accounts: [
    CatalogAccount(
      id: 'acc-nomina',
      name: 'Cuenta Nomina Bancolombia',
      currency: 'COP',
    ),
    CatalogAccount(
      id: 'acc-davivienda',
      name: 'Ahorros Davivienda Personal',
      currency: 'COP',
    ),
  ],
  categories: [
    CatalogCategory(id: 'cat-market', name: 'Mercado', type: 'E'),
    CatalogCategory(id: 'cat-food', name: 'Restaurantes', type: 'E'),
    CatalogCategory(id: 'cat-salary', name: 'Salario', type: 'I'),
  ],
);

const _cardMap = {'4412': 'acc-nomina', '9911': 'acc-davivienda'};

const _statement = '''
Banco Ficticio S.A. NIT 900.123.456-7
Titular: JUAN PEREZ GOMEZ
Documento: CC 1.032.456.789 (1032456789)
Cuenta de ahorros No. 12345678901  Tarjeta ****4412
Correo: juan.perez@example.com  Celular: 300 123 4567
Saldo disponible: \$ 8.765.432,10
Saldo en cuenta: 2.500.000,00
Saldo inicial: \$ 100.000,00
Fecha Descripcion Valor
01/10/2026 PAGO A 3001234567 -10.000,00
02/10/2026 COMPRA TIENDA D1 -20.000,00
03/10/2026 ABONO NOMINA EMPRESA 50.000,00
Saldo final: \$ 120.000,00
''';

void _expectClean(_Request request) {
  for (final secret in _forbidden) {
    expect(request.text, isNot(contains(secret)), reason: secret);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <String, _Request>{};

  tearDown(() => AiService.debugClientOverride = null);

  test(
    'receipt: categories only, metadata stripped, account resolved on the phone',
    () async {
      final client = _CapturingClient(
        (_) =>
            '{"date":"2026-11-03","merchant":"Drogueria","total":67300,"category_id":"cat-market","card_last4":"4412","warning":null}',
      );
      final draft =
          await ReceiptAnalyzer(
            clientProvider: () async => client,
            catalogLoader: () async => _catalog,
            accountForLast4: (last4) async => _cardMap[last4],
            parseAmount: (raw) => double.tryParse(raw),
            now: () => DateTime(2026, 11, 4),
          ).analyze(
            imageBytes: jpegWithMetadata(),
            filePath: '/docs/r.jpg',
            fileName: 'r.jpg',
          );

      final request = client.requests.single;
      requests['receipt'] = request;
      expect(draft.proposals.single.accountId, 'acc-nomina');
      expect(draft.proposals.single.categoryId, 'cat-market');
      _expectClean(request);
      expect(request.text, contains('"id":"cat-market"'));
      expect(request.text, isNot(contains('cat-salary')));
      expect(request.text, isNot(contains('account_id')));
      expect(request.maxTokens, AiTokenCaps.receipt);
      final sent = request.messages.last.images.single.bytes;
      expect(latin1.decode(sent), isNot(contains('Exif')));
      expect(latin1.decode(sent), isNot(contains('GPS')));
      expect(sent, isNot(equals(jpegWithMetadata())));
    },
  );

  test('statement: masked movement lines and the categories only', () async {
    final client = _CapturingClient(
      (_) => jsonEncode({
        'filas': [
          {'fecha': '01/10/2026', 'descripcion': 'PAGO', 'valor': '-10000'},
        ],
        'saldo_inicial': '100000',
        'saldo_final': '90000',
      }),
    );
    await StatementImporter(
      amountParser: (raw) => double.tryParse(raw),
      catalogLoader: () async => _catalog,
      clientLoader: () async => client,
    ).parseWithAi(_statement, 'acc-nomina');

    final request = client.requests.single;
    requests['statement'] = request;
    _expectClean(request);
    expect(request.text, contains(_catalog.categoriesForPrompt()));
    expect(request.text, isNot(contains('"accounts"')));
    expect(request.text, contains('01/10/2026 PAGO A [phone] -10.000,00'));
    expect(request.maxTokens, AiTokenCaps.statement);
  });

  test(
    'statement categories: categories, and per row index, description and sign',
    () async {
      final client = _CapturingClient((_) => '{"rows":[]}');
      final result = StatementResult(
        [
          for (final (i, title) in [
            'PAGO A 3001234567',
            'COMPRA TARJETA ****4412',
            'ABONO CC 1032456789',
          ].indexed)
            ProposedTransaction(
              date: DateTime(2026, 10, 1 + i),
              title: title,
              amount: 1000,
              type: i == 2 ? TransactionType.income : TransactionType.expense,
              accountId: 'acc-nomina',
            ),
        ],
        null,
        null,
      );

      await StatementImporter(
        catalogLoader: () async => _catalog,
        clientLoader: () async => client,
      ).proposeCategories(result);

      final request = client.requests.single;
      requests['categorize'] = request;
      _expectClean(request);
      final rows = jsonDecode(request.messages.last.text) as List;
      expect(rows, hasLength(3));
      for (final row in rows) {
        expect(
          (row as Map).keys,
          unorderedEquals(['i', 'descripcion', 'signo']),
        );
      }
      expect(request.text, contains('"id":"cat-salary"'));
      expect(request.maxTokens, AiTokenCaps.categorize);
    },
  );

  test(
    'recategorize: categories, and per transaction title and sign',
    () async {
      final db = AppDB.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final client = _CapturingClient((_) => '{"items":[]}');

      await RecategorizeService(
        client: client,
        catalog: _catalog,
        transactions: TransactionService.forTesting(db),
      ).propose(const [
        RecategorizeItem(id: 't1', title: 'Pago 3001234567', amount: 8765432),
        RecategorizeItem(
          id: 't2',
          title: 'Nomina Cuenta Nomina Bancolombia',
          amount: 2500000,
          isIncome: true,
        ),
      ]);

      final request = client.requests.single;
      requests['recategorize'] = request;
      final nameLess = request.text.replaceAll('Cuenta Nomina Bancolombia', '');
      for (final secret in _forbidden.where(
        (s) => s != 'Cuenta Nomina Bancolombia',
      )) {
        expect(nameLess, isNot(contains(secret)), reason: secret);
      }
      final rows =
          jsonDecode(request.messages.last.text.split('Transactions: ').last)
              as List;
      for (final row in rows) {
        expect((row as Map).keys, unorderedEquals(['n', 'title', 'sign']));
      }
      expect((rows[0] as Map)['sign'], '-');
      expect((rows[1] as Map)['sign'], '+');
      expect(request.text, isNot(contains('"accounts"')));
      expect(request.maxTokens, AiTokenCaps.recategorize);
    },
  );

  test('weekly summary: aggregates only', () async {
    await useTestConsent();
    final client = _CapturingClient((_) => '{"tips":["Gasta menos"]}');
    final previous = AiService.instance;
    AiService.instance = _FixedAiService(client);
    addTearDown(() => AiService.instance = previous);
    final now = DateTime(2026, 11, 4, 15);

    await InsightsServiceImpl(
      loadExpenses: (start, end) async => [
        InsightTransaction(
          title: 'Pago 3001234567',
          amount: 30000,
          date: DateTime(2026, 11, 2),
          categoryId: 'food',
          categoryName: 'Comida',
        ),
      ],
      preferredCurrency: () async => const CurrencyInDB(
        code: 'COP',
        symbol: r'$',
        name: 'Peso',
        decimalPlaces: 0,
        isDefault: true,
        type: 0,
      ),
      languageName: () => 'Spanish',
      now: () => now,
    ).weeklySummary();

    final request = client.requests.single;
    requests['insights'] = request;
    _expectClean(request);
    expect(request.text, isNot(contains('Pago')));
    expect(request.maxTokens, AiTokenCaps.insights);
  });

  test('every action was audited and carries a token cap', () {
    expect(requests.keys, {
      'receipt',
      'statement',
      'categorize',
      'recategorize',
      'insights',
    });
    for (final entry in requests.entries) {
      expect(entry.value.maxTokens, isNotNull, reason: entry.key);
    }
  });
}

class _FixedAiService implements AiService {
  _FixedAiService(this.fake);
  final AiClient? fake;

  @override
  Future<bool> isConfigured() async => fake != null;

  @override
  Future<AiClient> client() async => fake!;
}
