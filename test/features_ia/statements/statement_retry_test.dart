// A statement the AI reads that does not reconcile is asked once more with the whole masked text.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/privacy/statement_redaction.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';

const _text = '''
Titular: JUAN PEREZ GOMEZ
Documento: CC 1.032.456.789
Cuenta de ahorros No. 12345678901
Nota del banco sin numeros
Saldo inicial: \$ 100.000,00
Fecha Descripcion Valor
01/10/2026 PAGO A 3001234567 -10.000,00
02/10/2026 COMPRA TIENDA -20.000,00
03/10/2026 ABONO NOMINA 50.000,00
Saldo final: \$ 120.000,00
''';

String _answer({required String finalBalance}) => jsonEncode({
  'filas': [
    {'fecha': '01/10/2026', 'descripcion': 'PAGO', 'valor': '-10000'},
    {'fecha': '02/10/2026', 'descripcion': 'COMPRA', 'valor': '-20000'},
    {'fecha': '03/10/2026', 'descripcion': 'ABONO', 'valor': '50000'},
  ],
  'saldo_inicial': '100000',
  'saldo_final': finalBalance,
});

final _reconciled = _answer(finalBalance: '120000');
final _off = _answer(finalBalance: '130000');
final _alsoOff = _answer(finalBalance: '140000');

class _Client implements AiClient {
  _Client(this.answers);
  final List<String> answers;
  final sent = <String>[];

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    sent.add(messages.last.text);
    return AiResult(text: answers[sent.length - 1]);
  }

  @override
  Future<List<String>> listModels() async => const [];
}

Future<StatementResult> _read(_Client client, {String text = _text}) =>
    StatementImporter(
      amountParser: double.tryParse,
      catalogLoader: () async => const AiCatalog(accounts: [], categories: []),
      clientLoader: () async => client,
    ).parseWithAi(text, 'account');

void main() {
  test('the first reading reconciles: one call', () async {
    final client = _Client([_reconciled]);

    final result = await _read(client);

    expect(client.sent, hasLength(1));
    expect(client.sent.single, redactStatementText(_text));
    expect(client.sent.single, isNot(contains('Nota del banco')));
    expect(result.difference, 0);
  });

  test(
    'it does not reconcile and then does: the second is used, with the whole masked text',
    () async {
      final client = _Client([_off, _reconciled]);

      final result = await _read(client);

      expect(client.sent, hasLength(2));
      expect(client.sent[1], redactStatementText(_text, reduce: false));
      expect(client.sent[1], contains('Nota del banco sin numeros'));
      expect(client.sent[1], contains('JUAN PEREZ'));
      for (final secret in ['1.032.456.789', '12345678901', '3001234567']) {
        expect(client.sent[1], isNot(contains(secret)), reason: secret);
      }
      expect(result.finalBalance, 120000);
      expect(result.difference, 0);
    },
  );

  test(
    'neither reconciles: two calls, the first result and its difference stay',
    () async {
      final client = _Client([_off, _alsoOff]);

      final result = await _read(client);

      expect(client.sent, hasLength(2));
      expect(result.finalBalance, 130000);
      expect(result.difference, -10000);
    },
  );

  test('a failing second call keeps the first result', () async {
    final client = _Client([_off, 'not json']);

    final result = await _read(client);

    expect(client.sent, hasLength(2));
    expect(result.finalBalance, 130000);
  });

  test('without balances there is nothing to compare: one call', () async {
    final client = _Client([
      jsonEncode({
        'filas': [
          {'fecha': '01/10/2026', 'descripcion': 'PAGO', 'valor': '-10000'},
        ],
      }),
    ]);

    final result = await _read(client);

    expect(client.sent, hasLength(1));
    expect(result.difference, isNull);
  });

  test('a statement longer than one request is not retried', () async {
    final rows = [
      for (var i = 0; i < 400; i++)
        '${(i % 28 + 1).toString().padLeft(2, '0')}/10/2026 COMPRA TIENDA NUMERO $i 1.000,00',
    ].join('\n');
    final client = _Client([_off, _off, _off, _off]);

    await _read(
      client,
      text: 'Saldo inicial: 100.000,00\n$rows\nSaldo final: 120.000,00',
    );

    // One call per chunk; the whole text never goes a second time.
    expect(client.sent, hasLength(2));
  });
}
