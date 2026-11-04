import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/dedupe/dedupe.dart';

DedupeCandidate candidate({
  String title = 'Éxito Suba',
  DateTime? date,
  double amount = 45900,
  String accountId = 'bancolombia',
  TransactionType type = TransactionType.expense,
}) => DedupeCandidate(
  date: date ?? DateTime(2026, 10, 15, 12),
  amount: amount,
  accountId: accountId,
  type: type,
  title: title,
);

DedupeCandidate stored(DedupeCandidate row, String id) => DedupeCandidate(
  date: row.date,
  amount: row.amount,
  accountId: row.accountId,
  type: row.type,
  title: row.title,
  id: id,
);

List<DedupeCandidate> sampleBatch() => [
  candidate(title: 'Éxito Suba'),
  candidate(title: 'Carulla', amount: 12000, date: DateTime(2026, 10, 16, 8)),
  candidate(
    title: 'Transferencia Nequi',
    amount: 30000,
    type: TransactionType.income,
    date: DateTime(2026, 10, 17),
  ),
];

void main() {
  group('normalizeTitle', () {
    test('lowercases, drops accents, punctuation and the origin suffix', () {
      expect(normalizeTitle('COMPRA Éxito - Suba'), 'compra exito suba');
      expect(normalizeTitle('  éxito  [origen: bancolombia-2026-10]'), 'exito');
      expect(normalizeTitle('Café #123'), 'cafe 123');
      expect(normalizeTitle('Niño'), 'nino');
      expect(normalizeTitle('  compra   exito___suba '), 'compra exito suba');
    });

    test(
      'is empty when only the origin suffix, blanks or punctuation are left',
      () {
        expect(normalizeTitle('[origen: inbox:123]'), '');
        expect(normalizeTitle('   '), '');
        expect(normalizeTitle('---'), '');
      },
    );
  });

  group('findDuplicates', () {
    test(
      'reimporting the same batch marks every row as a duplicate of its own transaction',
      () {
        final batch = sampleBatch();
        final existing = [
          for (var i = 0; i < batch.length; i++) stored(batch[i], 'tx-$i'),
        ];

        final matches = findDuplicates(batch, existing);

        expect(matches.map((m) => m.rowIndex), [0, 1, 2]);
        expect(matches.map((m) => m.existingId), ['tx-0', 'tx-1', 'tx-2']);
        expect(matches.every((m) => m.otherRowIndex == null), isTrue);
      },
    );

    test(
      'every row that repeats an existing transaction matches it, as in T001',
      () {
        final rows = [candidate(title: 'Café'), candidate(title: 'Café')];
        final existing = [stored(rows[0], 'tx-a')];

        final matches = findDuplicates(rows, existing);

        expect(matches.map((m) => m.rowIndex), [0, 1]);
        expect(matches.map((m) => m.existingId), ['tx-a', 'tx-a']);
      },
    );

    test(
      'a row repeating a kept row of the batch is reported against the batch first',
      () {
        final rows = [
          candidate(title: 'Café', date: DateTime(2026, 10, 15, 12)),
          candidate(title: 'Café', date: DateTime(2026, 10, 16, 12)),
        ];
        final existing = [
          stored(
            candidate(title: 'Café', date: DateTime(2026, 10, 17, 12)),
            'tx-1',
          ),
        ];

        final match = findDuplicates(rows, existing).single;

        expect(match.rowIndex, 1);
        expect(match.reason, 'batch');
        expect(match.otherRowIndex, 0);
        expect(match.existingId, isNull);
      },
    );

    test(
      'a row repeated inside the batch is a duplicate of the earlier row',
      () {
        final rows = [
          candidate(title: 'Éxito Suba'),
          candidate(
            title: 'COMPRA EXITO SUBA',
            date: DateTime(2026, 10, 16, 9),
          ),
        ];

        final match = findDuplicates(rows, []).single;

        expect(match.rowIndex, 1);
        expect(match.otherRowIndex, 0);
        expect(match.existingId, isNull);
        expect(match.reason, 'batch');
      },
    );

    test('two empty titles on the same calendar day are duplicates', () {
      final rows = [candidate(title: '', date: DateTime(2026, 10, 15, 8))];
      final existing = [
        stored(
          candidate(title: '[origen: x]', date: DateTime(2026, 10, 15, 20)),
          'tx-1',
        ),
      ];

      expect(findDuplicates(rows, existing).single.existingId, 'tx-1');
    });

    test(
      'two empty titles 7 hours apart but on different calendar days are not duplicates',
      () {
        final rows = [candidate(title: '', date: DateTime(2026, 10, 15, 23))];
        final existing = [
          stored(candidate(title: '', date: DateTime(2026, 10, 16, 6)), 'tx-1'),
        ];

        expect(findDuplicates(rows, existing), isEmpty);
      },
    );

    test('two empty titles out of the one-day window are not duplicates', () {
      final rows = [candidate(title: '', date: DateTime(2026, 10, 15, 8))];
      final existing = [
        stored(candidate(title: '', date: DateTime(2026, 10, 17, 8)), 'tx-1'),
      ];

      expect(findDuplicates(rows, existing), isEmpty);
    });

    test('an empty title never matches a title with letters or digits', () {
      for (final (row, other) in [
        ('', 'Carulla'),
        ('Carulla', '[origen: x]'),
        ('---', 'Carulla'),
      ]) {
        final matches = findDuplicates(
          [candidate(title: row)],
          [stored(candidate(title: other), 'tx-1')],
        );

        expect(matches, isEmpty, reason: '"$row" against "$other"');
      }
    });

    test(
      'dates up to one day apart are duplicates, one minute more is not',
      () {
        final existing = [
          stored(candidate(date: DateTime(2026, 10, 15, 12)), 'tx-1'),
        ];

        expect(
          findDuplicates([
            candidate(date: DateTime(2026, 10, 16, 12)),
          ], existing).single.existingId,
          'tx-1',
        );
        expect(
          findDuplicates([
            candidate(date: DateTime(2026, 10, 16, 12, 1)),
          ], existing),
          isEmpty,
        );
      },
    );

    test('account, type and amount must all match', () {
      final existing = [stored(candidate(), 'tx-1')];

      expect(
        findDuplicates([candidate(accountId: 'nequi')], existing),
        isEmpty,
      );
      expect(
        findDuplicates([candidate(type: TransactionType.income)], existing),
        isEmpty,
      );
      expect(findDuplicates([candidate(amount: 45901)], existing), isEmpty);
    });

    test('titles match when the normalized words of one contain the other', () {
      final existing = [stored(candidate(title: 'Éxito'), 'tx-1')];

      expect(
        findDuplicates([
          candidate(title: 'COMPRA Éxito Suba'),
        ], existing).single.existingId,
        'tx-1',
      );
      expect(findDuplicates([candidate(title: 'Carulla')], existing), isEmpty);
      expect(
        findDuplicates(
          [candidate(title: 'Exito Suba')],
          [stored(candidate(title: 'Éxito'), 'tx-2')],
        ).single.existingId,
        'tx-2',
      );
    });
  });
}
