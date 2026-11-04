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

/// Answers every row of the prompt with the category [pick] chooses for it.
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
        final client = _FakeClient(
          (messages) async => _answer(
            messages,
            (row) => row['signo'] == '+' ? 'cat-i' : 'cat-e',
          ),
        );

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
  });
}
