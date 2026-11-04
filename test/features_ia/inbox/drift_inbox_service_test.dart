import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/models/transaction/transaction_status.enum.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';

import 'inbox_test_helpers.dart';

void main() {
  late InboxTestEnv env;

  setUp(() async => env = await InboxTestEnv.create());
  tearDown(() => env.close());

  Future<List<String>> tagNamesOf(String transactionId) async {
    final query = env.db.select(env.db.tags).join([
      innerJoin(
        env.db.transactionTags,
        env.db.transactionTags.tagID.equalsExp(env.db.tags.id),
      ),
    ])..where(env.db.transactionTags.transactionID.equals(transactionId));

    return (await query.get()).map((r) => r.read(env.db.tags.name)!).toList();
  }

  group('confirm creates the transactions', () {
    test(
      'with the ia tag, the origin in the notes and a signed value',
      () async {
        final id = await env.service.addItem(
          draft([
            row(title: 'KFC', amount: 45900),
            ProposedTransaction(
              date: DateTime(2026, 10, 25),
              title: 'Nomina',
              amount: 3000000,
              type: TransactionType.income,
              categoryId: 'cat-i',
              accountId: 'acc-1',
              notes: 'Octubre',
            ),
          ]),
        );

        final item = (await env.service.getItem(id))!;
        final result = await env.service.confirm(id, item.proposals);

        expect(result.errors, isEmpty);
        expect(result.duplicates, isEmpty);
        expect(result.createdIds, hasLength(2));

        final stored = await env.transactions();
        expect(stored, hasLength(2));

        final expense = stored.firstWhere((t) => t.title == 'KFC');
        expect(expense.value, -45900);
        expect(expense.type, TransactionType.expense);
        expect(expense.notes, '[origen: recibo:recibo-01.jpg]');
        expect(expense.categoryID, 'cat-e');
        expect(expense.status, isNull);
        expect(await tagNamesOf(expense.id), ['ia']);

        final income = stored.firstWhere((t) => t.title == 'Nomina');
        expect(income.value, 3000000);
        expect(income.notes, 'Octubre\n[origen: recibo:recibo-01.jpg]');

        final after = (await env.service.getItem(id))!;
        expect(after.status, InboxStatus.processed);
        expect(after.resultTransactionIds, unorderedEquals(result.createdIds));
      },
    );

    test('with the origin prefix of each source', () async {
      for (final (source, ref) in [
        (InboxSource.statement, 'bancolombia-2026-10'),
        (InboxSource.notification, 'com.nequi.MobileApp'),
      ]) {
        final id = await env.service.addItem(
          draft(
            [row(title: ref, amount: 1000.0 + ref.length)],
            source: source,
            ref: ref,
          ),
        );
        await env.service.confirm(
          id,
          (await env.service.getItem(id))!.proposals,
        );
      }

      final notes = (await env.transactions()).map((t) => t.notes).toSet();
      expect(notes, {
        '[origen: extracto:bancolombia-2026-10]',
        '[origen: aviso:com.nequi.MobileApp]',
      });
    });

    test('reusing the ia tag instead of creating another one', () async {
      for (final title in ['Uno', 'Dos']) {
        final id = await env.service.addItem(
          draft([row(title: title, amount: 1000.0 + title.length)]),
        );
        await env.service.confirm(
          id,
          (await env.service.getItem(id))!.proposals,
        );
      }

      final tags = await env.db.select(env.db.tags).get();
      expect(tags.where((t) => t.name == 'ia'), hasLength(1));
      expect(await env.db.select(env.db.transactionTags).get(), hasLength(2));
    });

    test('a future date is created as pending', () async {
      final id = await env.service.addItem(
        draft([row(date: DateTime.now().add(const Duration(days: 3)))]),
      );
      await env.service.confirm(id, (await env.service.getItem(id))!.proposals);

      expect(
        (await env.transactions()).single.status,
        TransactionStatus.pending,
      );
    });
  });

  group('confirm does not duplicate', () {
    test('confirming the same batch again creates nothing', () async {
      final rows = [
        row(title: 'KFC', amount: 45900),
        row(title: 'Exito', amount: 120000),
      ];

      final first = await env.service.addItem(draft(rows));
      final firstResult = await env.service.confirm(first, rows);
      expect(firstResult.createdIds, hasLength(2));

      // Same item: it is already processed.
      final again = await env.service.confirm(first, rows);
      expect(again.createdIds, isEmpty);

      // A new item with the same rows, as when a statement is imported twice.
      final second = await env.service.addItem(draft(rows));
      final secondResult = await env.service.confirm(second, rows);

      expect(secondResult.createdIds, isEmpty);
      expect(secondResult.duplicates.map((d) => d.rowIndex), [0, 1]);
      expect(
        secondResult.duplicates.map((d) => d.existingTransactionId),
        firstResult.createdIds,
      );
      expect(await env.transactions(), hasLength(2));
      expect(
        (await env.service.getItem(second))!.status,
        InboxStatus.processed,
      );
    });

    test(
      'a duplicate the user forces is created, one that is not is skipped',
      () async {
        final first = await env.service.addItem(draft([row(title: 'KFC')]));
        await env.service.confirm(first, [row(title: 'KFC')]);

        final rows = [row(title: 'KFC'), row(title: 'KFC')];
        final second = await env.service.addItem(draft(rows));
        rows[1].allowDuplicate = true;

        final result = await env.service.confirm(second, rows);

        // Row 0 matches the stored one and stays out; row 1 is forced in.
        expect(result.createdIds, hasLength(1));
        expect(result.duplicates.map((d) => d.rowIndex), [0]);
        expect(await env.transactions(), hasLength(2));
      },
    );

    test('forcing does not recreate what the item already created', () async {
      final rows = [
        row(title: 'KFC'),
        row(title: 'Exito', amount: 120000, categoryId: 'no-existe'),
      ];
      final id = await env.service.addItem(draft(rows));
      await env.service.confirm(id, rows);

      rows[1].categoryId = 'cat-e';
      rows[0].allowDuplicate = true;
      final retry = await env.service.confirm(id, rows);

      expect(retry.createdIds, hasLength(1));
      expect(await env.transactions(), hasLength(2));
    });

    test('equal rows inside the same batch create one', () async {
      final rows = [row(title: 'KFC'), row(title: 'KFC')];
      final id = await env.service.addItem(draft(rows));

      final result = await env.service.confirm(id, rows);

      expect(result.createdIds, hasLength(1));
      expect(result.duplicates.single.rowIndex, 1);
      expect(result.duplicates.single.existingTransactionId, isEmpty);
    });

    test('the same amount on another account is not a duplicate', () async {
      final rows = [
        row(title: 'KFC'),
        row(title: 'KFC', accountId: 'acc-2', date: DateTime(2026, 10, 20)),
      ];
      final id = await env.service.addItem(draft(rows));

      final result = await env.service.confirm(id, rows);

      expect(result.createdIds, hasLength(2));
    });

    test(
      'previewDuplicates reports a stored transaction before confirming',
      () async {
        final rows = [row(title: 'KFC')];
        final first = await env.service.addItem(draft(rows));
        await env.service.confirm(first, rows);

        final warnings = await env.service.previewDuplicates(rows);

        expect(warnings.single.rowIndex, 0);
        expect(await env.transactions(), hasLength(1));
      },
    );
  });

  group('a failing row', () {
    test(
      'keeps the item pending and the corrected retry does not duplicate',
      () async {
        final rows = [
          row(title: 'KFC', amount: 45900),
          row(title: 'Exito', amount: 120000, categoryId: 'no-existe'),
        ];
        final id = await env.service.addItem(draft(rows));

        final first = await env.service.confirm(id, rows);

        expect(first.createdIds, hasLength(1));
        expect(first.errors.keys, [1]);
        expect(first.errors[1], isNotEmpty);

        final pending = (await env.service.getItem(id))!;
        expect(pending.status, InboxStatus.pending);
        expect(pending.resultTransactionIds, first.createdIds);
        expect(await env.transactions(), hasLength(1));

        // The user fixes the category and confirms the whole list again.
        rows[1].categoryId = 'cat-e';
        final retry = await env.service.confirm(id, rows);

        expect(retry.errors, isEmpty);
        expect(retry.createdIds, hasLength(1));
        expect(
          retry.duplicates,
          isEmpty,
          reason: 'row 0 is a leftover of the first attempt',
        );
        expect(await env.transactions(), hasLength(2));

        final done = (await env.service.getItem(id))!;
        expect(done.status, InboxStatus.processed);
        expect(done.resultTransactionIds, hasLength(2));
        expect(done.resultTransactionIds.toSet(), {
          ...first.createdIds,
          ...retry.createdIds,
        });
      },
    );

    test('rejects what cannot be written, with a message per row', () async {
      final rows = [
        row(title: 'zero', amount: 0),
        row(title: 'negative', amount: -5),
        row(title: 'no account', accountId: null),
        row(title: 'unknown account', accountId: 'nope'),
        row(title: 'no category', categoryId: null),
        ProposedTransaction(
          date: DateTime(2026, 10, 20),
          title: 'transfer',
          amount: 10,
          type: TransactionType.transfer,
          categoryId: 'cat-e',
          accountId: 'acc-1',
        ),
        row(title: 'good', amount: 999),
      ];
      final id = await env.service.addItem(draft(rows));

      final result = await env.service.confirm(id, rows);

      expect(result.errors.keys, [0, 1, 2, 3, 4, 5]);
      expect(result.createdIds, hasLength(1));
      expect((await env.transactions()).single.title, 'good');
      expect((await env.service.getItem(id))!.status, InboxStatus.pending);
    });

    test(
      'warns instead of failing when the date is before the account was opened',
      () async {
        final rows = [row(accountId: 'acc-2', date: DateTime(2026, 1, 5))];
        final id = await env.service.addItem(draft(rows));

        final result = await env.service.confirm(id, rows);

        expect(result.createdIds, isEmpty);
        expect(result.errors.keys, [0]);
        expect(await env.transactions(), isEmpty);
        expect((await env.service.getItem(id))!.status, InboxStatus.pending);

        rows[0].date = DateTime(2026, 7, 5);
        final retry = await env.service.confirm(id, rows);

        expect(retry.errors, isEmpty);
        expect(retry.createdIds, hasLength(1));
      },
    );
  });

  group('attachments', () {
    Future<List<(String, String)>> attachments() async =>
        (await env.db.select(env.db.transactionAttachments).get())
            .map((a) => (a.transactionID, a.filePath))
            .toList();

    test('are linked to the first transaction created', () async {
      final rows = [
        row(title: 'KFC', amount: 45900),
        row(title: 'Exito', amount: 120000),
      ];
      final id = await env.service.addItem(
        draft(rows, attachments: ['/docs/a.jpg', '/docs/b.jpg']),
      );

      final result = await env.service.confirm(id, rows);

      expect(await attachments(), [
        (result.createdIds.first, '/docs/a.jpg'),
        (result.createdIds.first, '/docs/b.jpg'),
      ]);
    });

    test('are linked once, to the first row that gets created', () async {
      final rows = [
        row(title: 'KFC', amount: 45900, categoryId: 'no-existe'),
        row(title: 'Exito', amount: 120000),
      ];
      final id = await env.service.addItem(
        draft(rows, attachments: ['/docs/a.jpg']),
      );

      final first = await env.service.confirm(id, rows);
      expect(await attachments(), [(first.createdIds.single, '/docs/a.jpg')]);

      rows[0].categoryId = 'cat-e';
      await env.service.confirm(id, rows);

      expect(await attachments(), [(first.createdIds.single, '/docs/a.jpg')]);
    });

    test('are deleted with their transaction', () async {
      final rows = [row()];
      final id = await env.service.addItem(
        draft(rows, attachments: ['/docs/a.jpg']),
      );
      final result = await env.service.confirm(id, rows);

      // Test databases leave foreign keys off, the app turns them on when opening.
      await env.db.customStatement('PRAGMA foreign_keys = ON');
      await env.service.transactions.deleteTransaction(
        result.createdIds.single,
      );

      expect(await attachments(), isEmpty);
    });
  });

  group('items', () {
    test('addItem stores the draft as a pending item', () async {
      final id = await env.service.addItem(
        InboxDraft(
          source: InboxSource.notification,
          sourceRef: 'com.nequi.MobileApp',
          proposals: [row()],
          rawText: 'Pagaste 45.900 en KFC',
          attachmentPaths: ['/docs/a.jpg'],
          note: 'nota',
        ),
      );

      final item = (await env.service.getItem(id))!;

      expect(item.status, InboxStatus.pending);
      expect(item.source, InboxSource.notification);
      expect(item.sourceRef, 'com.nequi.MobileApp');
      expect(item.rawText, 'Pagaste 45.900 en KFC');
      expect(item.attachmentPaths, ['/docs/a.jpg']);
      expect(item.note, 'nota');
      expect(item.resultTransactionIds, isEmpty);
      expect(item.proposals.single.title, 'KFC');
      expect(item.proposals.single.amount, 45900);
      expect(await env.service.getItem('missing'), isNull);
    });

    test('discard marks the item and keeps the reason', () async {
      final id = await env.service.addItem(draft([row()]));

      await env.service.discard(id, reason: 'Not mine');

      final item = (await env.service.getItem(id))!;
      expect(item.status, InboxStatus.discarded);
      expect(item.note, 'Not mine');
      expect(await env.transactions(), isEmpty);
    });

    test('a discarded item cannot be confirmed', () async {
      final rows = [row()];
      final id = await env.service.addItem(draft(rows));
      await env.service.discard(id);

      final result = await env.service.confirm(id, rows);

      expect(result.createdIds, isEmpty);
      expect(await env.transactions(), isEmpty);
    });

    test(
      'watchItems filters by status and watchPendingCount follows it',
      () async {
        final a = await env.service.addItem(
          draft([row(title: 'A')], ref: 'a.jpg'),
        );
        final b = await env.service.addItem(
          draft([row(title: 'B', amount: 100)], ref: 'b.jpg'),
        );
        await env.service.addItem(
          draft([row(title: 'C', amount: 200)], ref: 'c.jpg'),
        );

        await env.service.confirm(a, [row(title: 'A')]);
        await env.service.discard(b);

        expect((await env.service.watchItems().first), hasLength(3));
        expect(
          (await env.service.watchItems(status: InboxStatus.pending).first).map(
            (i) => i.sourceRef,
          ),
          ['c.jpg'],
        );
        expect(
          (await env.service.watchItems(status: InboxStatus.processed).first)
              .map((i) => i.sourceRef),
          ['a.jpg'],
        );
        expect(
          (await env.service.watchItems(status: InboxStatus.discarded).first)
              .map((i) => i.sourceRef),
          ['b.jpg'],
        );
        expect(await env.service.watchPendingCount().first, 1);
      },
    );
  });
}
