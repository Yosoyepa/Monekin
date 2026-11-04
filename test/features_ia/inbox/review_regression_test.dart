import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/dedupe/dedupe.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';

import 'inbox_test_helpers.dart';

void main() {
  late InboxTestEnv env;
  setUp(() async => env = await InboxTestEnv.create(finder: findDuplicates));
  tearDown(() => env.close());

  test('finding 3: edited created row is never inserted again', () async {
    final rows = [
      row(title: 'first'),
      row(title: 'second', categoryId: 'missing'),
    ];
    final id = await env.service.addItem(draft(rows));
    final initial = (await env.service.getItem(id))!;
    final first = await env.service.confirm(id, rows);
    expect(first.createdIds, hasLength(1));
    final pending = (await env.service.getItem(id))!;
    expect(pending.proposals[0].id, initial.proposals[0].id);
    expect(pending.proposals[0].status, ProposalStatus.created);
    expect(pending.proposals[0].transactionId, first.createdIds.single);
    expect(pending.proposals[1].status, ProposalStatus.error);
    expect(pending.proposals[1].errorMessage, isNotEmpty);
    rows[0].title = 'accidental edit';
    rows[0].amount = 77;
    rows[1].categoryId = 'cat-e';
    expect((await env.service.confirm(id, rows)).createdIds, hasLength(1));
    expect(
      (await env.transactions()).map((t) => t.title),
      unorderedEquals(['first', 'second']),
    );
  });

  test('legacy partial item refuses an ambiguous retry', () async {
    final rows = [row(), row(title: 'Other', categoryId: 'missing')];
    final id = await env.service.addItem(draft(rows));
    await env.service.confirm(id, rows);
    final dbRow = await (env.db.select(
      env.db.aiInboxItems,
    )..where((t) => t.id.equals(id))).getSingle();
    final legacy = (jsonDecode(dbRow.proposalsJson) as List)
        .cast<Map<String, dynamic>>();
    for (final proposal in legacy) {
      proposal.remove('id');
      proposal.remove('status');
      proposal.remove('transactionId');
      proposal.remove('errorMessage');
    }
    await (env.db.update(env.db.aiInboxItems)..where((t) => t.id.equals(id)))
        .write(AiInboxItemsCompanion(proposalsJson: Value(jsonEncode(legacy))));
    final a = (await env.service.getItem(id))!;
    final b = (await env.service.getItem(id))!;
    expect(a.proposals.first.id, b.proposals.first.id);
    rows[0].title = 'Edited';
    rows[1].categoryId = 'cat-e';
    expect((await env.service.confirm(id, rows)).errors, isNotEmpty);
    expect(await env.transactions(), hasLength(1));
  });

  test('finding 4: concurrent confirms create one set', () async {
    final rows = [row(title: 'first'), row(title: 'second', amount: 123)];
    final id = await env.service.addItem(draft(rows));
    await Future.wait([
      env.service.confirm(id, rows),
      env.service.confirm(id, rows),
    ]);
    expect(await env.transactions(), hasLength(2));
  });

  test(
    'finding 5: identical batch rows retain multiplicity on import and reimport',
    () async {
      final rows = [row(), row()];
      final id = await env.service.addItem(draft(rows));
      expect((await env.service.confirm(id, rows)).createdIds, hasLength(2));
      final again = [row(), row()];
      final second = await env.service.addItem(draft(again));
      final result = await env.service.confirm(second, again);
      expect(result.createdIds, isEmpty);
      expect(result.duplicates, hasLength(2));
      expect(await env.transactions(), hasLength(2));
    },
  );

  test(
    'explicitly skipped batch duplicate is persisted and reported',
    () async {
      final rows = [row(), row()..allowDuplicate = false];
      final id = await env.service.addItem(draft(rows));
      final result = await env.service.confirm(id, rows);
      expect(result.createdIds, hasLength(1));
      expect(result.duplicates.single.rowIndex, 1);
      expect(result.duplicates.single.reason, duplicateInBatch);
      final item = (await env.service.getItem(id))!;
      expect(item.proposals[1].status, ProposalStatus.skippedDuplicate);
      expect(item.proposals[1].errorMessage, duplicateInBatch);
    },
  );

  test(
    'finding 12: category type matches expense and income including both',
    () async {
      await env.db
          .into(env.db.categories)
          .insert(
            const CategoryInDB(
              id: 'cat-b',
              name: 'Both',
              iconId: 'wallet',
              color: '4385be',
              type: CategoryType.B,
              displayOrder: 0,
            ),
          );
      final rows = [
        row(title: 'bad expense', categoryId: 'cat-i'),
        row(title: 'bad income', categoryId: 'cat-e')
          ..type = TransactionType.income,
        row(title: 'both expense', categoryId: 'cat-b'),
        row(title: 'both income', categoryId: 'cat-b')
          ..type = TransactionType.income,
      ];
      final id = await env.service.addItem(draft(rows));
      final result = await env.service.confirm(id, rows);
      expect(result.errors.keys, unorderedEquals([0, 1]));
      expect(result.createdIds, hasLength(2));
    },
  );

  test('finding 13: adjacent local days match even over 24 hours', () {
    DedupeCandidate c(DateTime date) => DedupeCandidate(
      date: date,
      amount: 10,
      accountId: 'a',
      type: TransactionType.expense,
      title: 'shop',
    );
    for (final (a, b) in [
      (DateTime(2026, 10, 15, 0, 1), DateTime(2026, 10, 16, 23, 59)),
      (DateTime(2026, 10, 16, 23, 59), DateTime(2026, 10, 15, 0, 1)),
    ]) {
      expect(findDuplicates([c(a)], [c(b)]), hasLength(1));
    }
    expect(
      findDuplicates(
        [c(DateTime(2026, 10, 15, 23, 59))],
        [c(DateTime(2026, 10, 17, 0, 1))],
      ),
      isEmpty,
    );
  });
}
