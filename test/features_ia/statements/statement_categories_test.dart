import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';

const _catalog = AiCatalog(
  accounts: [CatalogAccount(id: 'acc-2', name: 'Nequi', currency: 'COP')],
  categories: [
    CatalogCategory(id: 'cat-e', name: 'Comida', type: 'E'),
    CatalogCategory(id: 'cat-x', name: 'Transporte', type: 'E'),
    CatalogCategory(id: 'cat-i', name: 'Salario', type: 'I'),
  ],
);

class _FakeClient implements AiClient {
  _FakeClient(this.respond);

  final Future<AiResult> Function(List<AiMessage> messages) respond;
  int calls = 0;

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) {
    calls++;
    return respond(messages);
  }

  @override
  Future<List<String>> listModels() async => [];
}

/// Answers every row of a category request with the category [pick] chooses.
AiResult _answer(
  List<AiMessage> messages,
  String Function(Map<String, dynamic> row) pick,
) {
  final rows = (jsonDecode(messages.last.text) as List)
      .cast<Map<String, dynamic>>();
  return AiResult(
    text: jsonEncode({
      'rows': [
        for (final row in rows) {'i': row['i'], 'categoryId': pick(row)},
      ],
    }),
  );
}

/// Expense rows get `cat-e` and income rows `cat-i`.
AiResult _bySign(List<AiMessage> messages) =>
    _answer(messages, (row) => row['signo'] == '+' ? 'cat-i' : 'cat-e');

/// Reads a statement text the way the model does, then answers the category
/// requests that the importer sends afterwards.
Future<AiResult> _readStatement(List<AiMessage> messages) async {
  if (messages.first.text.startsWith('Asigna')) return _bySign(messages);
  const amounts = [
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

Future<StatementResult> _parsedNequi() async {
  final text = await File(
    'test/features_ia/fixtures/statements/nequi_2026-10.csv',
  ).readAsString();
  return StatementImporter().parseCsv(text, 'acc-2')!;
}

void main() {
  group('proposeCategories', () {
    test(
      'fills the 8 Nequi rows with the categories the client returned, in one call',
      () async {
        final client = _FakeClient((messages) async => _bySign(messages));

        final result = await StatementImporter(
          catalogLoader: () async => _catalog,
          clientLoader: () async => client,
        ).proposeCategories(await _parsedNequi());

        expect(client.calls, 1);
        expect(result.categoryWarning, isFalse);
        expect(result.rows.map((row) => row.categoryId).toList(), [
          'cat-e',
          'cat-e',
          'cat-e',
          'cat-i',
          'cat-e',
          'cat-e',
          'cat-e',
          'cat-e',
        ]);
      },
    );

    test(
      'an unknown id or a category of another type leaves that row without category',
      () async {
        final client = _FakeClient(
          (messages) async => _answer(
            messages,
            (row) => switch (row['i']) {
              0 => 'no-existe',
              1 => 'cat-i',
              3 => 'cat-e',
              _ => 'cat-e',
            },
          ),
        );

        final result = await StatementImporter(
          catalogLoader: () async => _catalog,
          clientLoader: () async => client,
        ).proposeCategories(await _parsedNequi());

        expect(result.rows.map((row) => row.categoryId).toList(), [
          null,
          null,
          'cat-e',
          null,
          'cat-e',
          'cat-e',
          'cat-e',
          'cat-e',
        ]);
        expect(result.categoryWarning, isFalse);
      },
    );

    test(
      'a valid category already in a row is kept and not sent; an invalid one is sent again',
      () async {
        final sent = <String>[];
        final client = _FakeClient((messages) async {
          final rows = jsonDecode(messages.last.text) as List;
          sent.addAll([
            for (final row in rows) (row as Map)['descripcion'] as String,
          ]);
          return _bySign(messages);
        });
        final statement = await _parsedNequi();
        statement.rows[0].categoryId = 'cat-x';
        statement.rows[1].categoryId = 'cat-i';
        statement.rows[2].categoryId = 'no-existe';
        statement.rows[3].categoryId = 'cat-i';

        final result = await StatementImporter(
          catalogLoader: () async => _catalog,
          clientLoader: () async => client,
        ).proposeCategories(statement);

        expect(sent, hasLength(6));
        expect(sent, isNot(contains('Recarga celular')));
        expect(sent, isNot(contains('Recepcion de Maria Lopez')));
        expect(result.rows.map((row) => row.categoryId).toList(), [
          'cat-x',
          'cat-e',
          'cat-e',
          'cat-i',
          'cat-e',
          'cat-e',
          'cat-e',
          'cat-e',
        ]);
      },
    );

    test(
      'a failing call keeps the import going: 8 rows without category and a warning',
      () async {
        final client = _FakeClient((_) async {
          throw const AiException(AiErrorKind.network, 'offline');
        });

        final result = await StatementImporter(
          catalogLoader: () async => _catalog,
          clientLoader: () async => client,
        ).proposeCategories(await _parsedNequi());

        expect(result.rows, hasLength(8));
        expect(result.rows.every((row) => row.categoryId == null), isTrue);
        expect(result.categoryWarning, isTrue);
      },
    );

    test(
      'without a configured provider the rows keep no category and the result is flagged',
      () async {
        final result = await StatementImporter(
          catalogLoader: () async => _catalog,
        ).proposeCategories(await _parsedNequi());

        expect(result.rows.every((row) => row.categoryId == null), isTrue);
        expect(result.categoryWarning, isTrue);
      },
    );

    test(
      'rows the AI reads from a statement text get categories afterwards',
      () async {
        final text = await File(
          'test/features_ia/statements/bancolombia_extracted.txt',
        ).readAsString();
        final client = _FakeClient(_readStatement);
        final importer = StatementImporter(
          catalogLoader: () async => _catalog,
          clientLoader: () async => client,
        );

        final interpreted = await importer.parseWithAi(text, 'acc-2');
        expect(interpreted.rows.every((row) => row.categoryId == null), isTrue);

        final result = await importer.proposeCategories(interpreted);

        expect(client.calls, 2);
        expect(result.categoryWarning, isFalse);
        expect(result.rows.map((row) => row.categoryId).toList(), [
          'cat-i',
          'cat-e',
          'cat-e',
          'cat-e',
          'cat-e',
          'cat-e',
          'cat-i',
          'cat-e',
          'cat-e',
          'cat-e',
          'cat-e',
          'cat-e',
        ]);
      },
    );
  });
}
