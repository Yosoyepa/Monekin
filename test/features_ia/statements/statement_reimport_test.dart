import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';

import '../inbox/inbox_test_helpers.dart';

void main() {
  late InboxTestEnv env;

  setUp(() async => env = await InboxTestEnv.create());
  tearDown(() => env.close());

  test(
    'previewDuplicates warns about the 8 stored Nequi rows when they have no category',
    () async {
      final text = await File(
        'test/features_ia/fixtures/statements/nequi_2026-10.csv',
      ).readAsString();
      final importer = StatementImporter();

      final categorized = [
        for (final row in importer.parseCsv(text, 'acc-2')!.rows)
          ProposedTransaction(
            date: row.date,
            title: row.title,
            amount: row.amount,
            type: row.type,
            accountId: row.accountId,
            categoryId: row.type == TransactionType.income ? 'cat-i' : 'cat-e',
          ),
      ];
      final id = await env.service.addItem(
        draft(
          categorized,
          source: InboxSource.statement,
          ref: 'nequi_2026-10.csv',
        ),
      );
      final first = await env.service.confirm(id, categorized);
      expect(first.createdIds, hasLength(8));

      final reimport = importer.parseCsv(text, 'acc-2')!.rows;
      expect(reimport.every((row) => row.categoryId == null), isTrue);

      final warnings = await env.service.previewDuplicates(reimport);

      expect(
        warnings.map((w) => w.rowIndex),
        unorderedEquals(List.generate(8, (i) => i)),
      );
      expect(await env.transactions(), hasLength(8));
    },
  );
}
