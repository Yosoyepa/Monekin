import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';

import '../privacy/jpeg_fixture.dart';

class _FakeCatalog extends AiCatalog {
  const _FakeCatalog()
    : super(
        accounts: const [
          CatalogAccount(id: 'acc-cash', name: 'Cash', currency: 'COP'),
          CatalogAccount(id: 'acc-debit', name: 'Debit', currency: 'COP'),
        ],
        categories: const [
          CatalogCategory(id: 'cat-food', name: 'Food', type: 'E'),
          CatalogCategory(id: 'cat-salary', name: 'Salary', type: 'I'),
        ],
      );
}

class _FakeClient implements AiClient {
  _FakeClient(this.answer);

  final Object answer; // String body or an exception to throw
  List<AiMessage>? lastMessages;

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    lastMessages = messages;
    final a = answer;
    if (a is Exception) throw a;
    return AiResult(text: a as String);
  }

  @override
  Future<List<String>> listModels() async => [];
}

double? _fakeParse(String raw) => double.tryParse(
  raw.replaceAll(RegExp(r'[^\d,-]'), '').replaceAll(',', '.'),
);

ReceiptAnalyzer _analyzer(
  AiClient client, {
  Map<String, String> cards = const {},
}) => ReceiptAnalyzer(
  clientProvider: () async => client,
  catalogLoader: () async => const _FakeCatalog(),
  accountForLast4: (last4) async => cards[last4],
  parseAmount: _fakeParse,
  now: () => DateTime(2026, 11, 4, 10),
);

Future<ProposedTransaction?> _parse(
  Map<String, dynamic> json, {
  Map<String, String> cards = const {},
}) => parseReceiptResponse(
  json,
  catalog: const _FakeCatalog(),
  accountForLast4: (last4) async => cards[last4],
  parseAmount: _fakeParse,
  now: DateTime(2026, 11, 4, 10),
);

void main() {
  group('buildReceiptMessages', () {
    test('includes the categories, the Colombian rules and the image', () {
      final messages = buildReceiptMessages(
        categoriesJson: '{"categories":[{"id":"cat-food"}]}',
        imageBytes: Uint8List.fromList([1, 2, 3]),
        today: DateTime(2026, 11, 4),
      );

      final system = messages.first;
      expect(system.role, 'system');
      expect(system.text, contains('"id":"cat-food"'));
      expect(system.text, contains('dot for thousands'));
      expect(system.text, contains('dd/mm/yyyy'));
      expect(system.text, contains('suggested tip'));
      expect(system.text, contains('is NOT the total'));
      expect(system.text, contains('ONE transaction per receipt'));
      expect(system.text, isNot(contains('account_id')));
      expect(system.text, contains('2026-11-04'));

      final user = messages.last;
      expect(user.role, 'user');
      expect(user.images, hasLength(1));
      expect(user.images.single.bytes, [1, 2, 3]);
    });

    test('BUG-07: the total is the amount paid, never the suggested tip', () {
      final system = buildReceiptMessages(
        categoriesJson: '{}',
        imageBytes: Uint8List(1),
        today: DateTime(2026, 11, 4),
      ).first.text;

      expect(system, contains('"TOTAL" or "TOTAL A PAGAR"'));
      expect(system, contains('propina sugerida'));
      expect(system, contains('never answer a tip line or a subtotal line'));
      expect(system, contains('Copy its digits exactly'));
      expect(system, contains('several possible totals'));
      expect(system, contains('"warning"'));
    });

    test('asks for the card digits and carries no card map', () {
      final messages = buildReceiptMessages(
        categoriesJson: '{}',
        imageBytes: Uint8List(1),
        today: DateTime(2026, 11, 4),
      );
      expect(messages.first.text, contains('card_last4'));
      expect(messages.first.text, isNot(contains('Cards of the user')));
    });
  });

  group('parseReceiptResponse', () {
    test('a correct answer becomes one expense proposal', () async {
      final p = await _parse({
        'date': '2026-10-28',
        'merchant': 'ALMACENES EXITO',
        'total': 45900,
        'category_id': 'cat-food',
        'account_id': 'acc-cash',
        'card_last4': null,
        'warning': null,
      });

      expect(p, isNotNull);
      expect(p!.date, DateTime(2026, 10, 28));
      expect(p.title, 'ALMACENES EXITO');
      expect(p.amount, 45900);
      expect(p.type, TransactionType.expense);
      expect(p.categoryId, 'cat-food');
      expect(p.accountId, isNull);
      expect(p.warning, isNull);
    });

    test(
      'a total written as text «45.900» goes through the amount parser',
      () async {
        final p = await _parse({
          'date': '28/10/2026',
          'merchant': 'Exito',
          'total': r'$ 45.900',
        });

        expect(p!.amount, 45900);
        expect(p.date, DateTime(2026, 10, 28));
      },
    );

    test('ids missing from the catalog become null', () async {
      final p = await _parse({
        'date': '2026-10-28',
        'merchant': 'Exito',
        'total': 45900,
        'category_id': 'made-up-category',
        'account_id': 'made-up-account',
      });

      expect(p!.categoryId, isNull);
      expect(p.accountId, isNull);
    });

    test('an income category is not accepted for a receipt', () async {
      final p = await _parse({
        'date': '2026-10-28',
        'merchant': 'Exito',
        'total': 100,
        'category_id': 'cat-salary',
      });
      expect(p!.categoryId, isNull);
    });

    test(
      'last 4 digits pick the account from the card map, not the one the model names',
      () async {
        final p = await _parse(
          {
            'date': '2026-10-28',
            'merchant': 'Drogueria',
            'total': 45900,
            'account_id': 'acc-cash',
            'card_last4': '****4412',
          },
          cards: {'4412': 'acc-debit'},
        );

        expect(p!.accountId, 'acc-debit');
      },
    );

    test(
      'last 4 digits that are not mapped leave the account empty, even if the model names one',
      () async {
        final p = await _parse(
          {
            'date': '2026-10-28',
            'merchant': 'Drogueria',
            'total': 45900,
            'account_id': 'acc-cash',
            'card_last4': '9999',
          },
          cards: {'4412': 'acc-debit'},
        );

        expect(p!.accountId, isNull);
      },
    );

    test('a mapped account that is not in the catalog is dropped', () async {
      final p = await _parse(
        {
          'date': '2026-10-28',
          'merchant': 'Drogueria',
          'total': 45900,
          'card_last4': '4412',
        },
        cards: {'4412': 'deleted-account'},
      );

      expect(p!.accountId, isNull);
    });

    test('missing date and merchant use today and a warning', () async {
      final p = await _parse({'total': 18500, 'warning': 'Imagen borrosa'});

      expect(p!.date, DateTime(2026, 11, 4));
      expect(p.title, 'Receipt');
      expect(p.warning, contains('The date was not read'));
      expect(p.warning, contains('The merchant was not read'));
      expect(p.warning, contains('Imagen borrosa'));
    });

    test(
      'BUG-07: a warning about several totals reaches the proposal',
      () async {
        final p = await _parse({
          'merchant': 'RESTAURANTE',
          'total': 1234567,
          'warning': 'Hay varios totales: 1.234.567 y 1.122.334 sin propina',
        });

        expect(p!.amount, 1234567);
        expect(p.warning, contains('varios totales'));
      },
    );

    test('BUG-07: the digits of the total are not changed', () async {
      final p = await _parse({'merchant': 'RESTAURANTE', 'total': 1234567});
      final q = await _parse({'merchant': 'RESTAURANTE', 'total': '1.234.567'});

      expect(p!.amount, 1234567);
      expect(q!.amount, 1234567);
    });

    test('no valid total gives no proposal', () async {
      expect(await _parse({'merchant': 'Exito', 'total': 'abc'}), isNull);
      expect(await _parse({'merchant': 'Exito', 'total': 0}), isNull);
      expect(await _parse({'merchant': 'Exito', 'total': -5}), isNull);
      expect(await _parse({'merchant': 'Exito'}), isNull);
    });
  });

  group('ReceiptAnalyzer', () {
    final bytes = minimalJpeg();

    test(
      'a good answer gives a draft with one proposal and the photo attached',
      () async {
        final client = _FakeClient(
          '```json\n{"date":"2026-11-03","merchant":"Drogueria Ficticia SAS","total":67300,"category_id":"cat-food",'
          '"account_id":null,"card_last4":"9911","warning":null}\n```',
        );
        final draft = await _analyzer(client, cards: {'9911': 'acc-debit'})
            .analyze(
              imageBytes: bytes,
              filePath: '/docs/finanzas_ia/receipts/abc.jpg',
              fileName: 'abc.jpg',
            );

        expect(draft.source, InboxSource.receipt);
        expect(draft.sourceRef, 'abc.jpg');
        expect(draft.attachmentPaths, ['/docs/finanzas_ia/receipts/abc.jpg']);
        expect(draft.note, isNull);
        expect(draft.proposals.single.amount, 67300);
        expect(draft.proposals.single.accountId, 'acc-debit');
        expect(client.lastMessages!.first.text, contains('"id":"cat-food"'));
        expect(client.lastMessages!.last.images.single.bytes, bytes);
      },
    );

    for (final kind in AiErrorKind.values) {
      test(
        'an AI failure ($kind) keeps the receipt without a proposal and with the notice',
        () async {
          final draft = await _analyzer(_FakeClient(AiException(kind, 'boom')))
              .analyze(
                imageBytes: bytes,
                filePath: '/docs/r.jpg',
                fileName: 'r.jpg',
              );

          expect(draft.proposals, isEmpty);
          expect(draft.note, ReceiptMessages.defaultAiError(kind));
          expect(draft.attachmentPaths, ['/docs/r.jpg']);
        },
      );
    }

    test(
      'an answer that is not JSON keeps the receipt with a bad-response notice',
      () async {
        final draft = await _analyzer(_FakeClient('Sorry, I cannot read this'))
            .analyze(
              imageBytes: bytes,
              filePath: '/docs/r.jpg',
              fileName: 'r.jpg',
            );

        expect(draft.proposals, isEmpty);
        expect(
          draft.note,
          ReceiptMessages.defaultAiError(AiErrorKind.badResponse),
        );
      },
    );

    test(
      'JSON without a readable total keeps the receipt with the missing-total notice',
      () async {
        final draft =
            await _analyzer(
              _FakeClient('{"merchant":"Exito","total":null}'),
            ).analyze(
              imageBytes: bytes,
              filePath: '/docs/r.jpg',
              fileName: 'r.jpg',
            );

        expect(draft.proposals, isEmpty);
        expect(draft.note, 'The total was not read');
      },
    );

    test(
      'a photo that is not an image is not sent and keeps the notice',
      () async {
        final client = _FakeClient('{}');
        final draft = await _analyzer(client).analyze(
          imageBytes: Uint8List.fromList([9, 9, 9]),
          filePath: '/docs/r.bin',
          fileName: 'r.bin',
        );

        expect(client.lastMessages, isNull);
        expect(draft.proposals, isEmpty);
        expect(draft.note, const ReceiptMessages().unsupportedImage);
        expect(draft.attachmentPaths, ['/docs/r.bin']);
      },
    );

    test('a client that cannot be created is reported, not thrown', () async {
      final analyzer = ReceiptAnalyzer(
        clientProvider: () async =>
            throw const AiException(AiErrorKind.notConfigured, 'no key'),
        catalogLoader: () async => const _FakeCatalog(),
        accountForLast4: (_) async => null,
        parseAmount: _fakeParse,
      );
      final draft = await analyzer.analyze(
        imageBytes: bytes,
        filePath: '/docs/r.jpg',
        fileName: 'r.jpg',
      );

      expect(draft.proposals, isEmpty);
      expect(
        draft.note,
        ReceiptMessages.defaultAiError(AiErrorKind.notConfigured),
      );
    });
  });
}
