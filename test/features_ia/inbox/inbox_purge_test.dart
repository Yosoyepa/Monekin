import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:uuid/uuid.dart';

import 'inbox_test_helpers.dart';

void main() {
  final now = DateTime(2026, 11, 4, 12);
  final old = now.subtract(const Duration(days: 31));
  final recent = now.subtract(const Duration(days: 29));

  late InboxTestEnv env;
  late Directory root;
  late Directory receipts;
  late Directory elsewhere;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('inbox_purge');
    receipts = await Directory('${root.path}/receipts').create();
    elsewhere = await Directory('${root.path}/elsewhere').create();
    env = await InboxTestEnv.create(receiptsDir: receipts);
  });

  tearDown(() async {
    await env.close();
    await root.delete(recursive: true);
  });

  /// A photo named like the ones `saveReceiptPhoto` writes.
  Future<String> photo({Directory? dir, String? name}) async {
    final file = File(
      '${(dir ?? receipts).path}/${name ?? '${const Uuid().v4()}.jpg'}',
    );
    await file.writeAsBytes([1, 2, 3]);
    return file.path;
  }

  Future<void> insertItem(
    String id, {
    required String status,
    required DateTime createdAt,
    List<String> attachments = const [],
  }) {
    return env.db
        .into(env.db.aiInboxItems)
        .insert(
          AiInboxItemsCompanion.insert(
            id: id,
            source: InboxSource.receipt.name,
            sourceRef: 'recibo-$id.jpg',
            createdAt: createdAt,
            proposalsJson: '[]',
            status: Value(status),
            attachmentsJson: Value(jsonEncode(attachments)),
          ),
        );
  }

  Future<Set<String>> remainingIds() async {
    final rows = await env.db.select(env.db.aiInboxItems).get();
    return rows.map((row) => row.id).toSet();
  }

  test('purges processed and discarded items older than 30 days', () async {
    await insertItem('old-processed', status: 'processed', createdAt: old);
    await insertItem('old-discarded', status: 'discarded', createdAt: old);
    await insertItem('old-pending', status: 'pending', createdAt: old);
    await insertItem(
      'recent-processed',
      status: 'processed',
      createdAt: recent,
    );
    await insertItem(
      'recent-discarded',
      status: 'discarded',
      createdAt: recent,
    );

    final purged = await env.service.purgeOld(now: now);

    expect(purged, 2);
    expect(await remainingIds(), {
      'old-pending',
      'recent-processed',
      'recent-discarded',
    });
  });

  test('deletes the photos of old discarded items', () async {
    final discarded = await photo();
    await insertItem(
      'old-discarded',
      status: 'discarded',
      createdAt: old,
      attachments: [discarded],
    );

    await env.service.purgeOld(now: now);

    expect(File(discarded).existsSync(), isFalse);
  });

  test(
    'keeps the photos of old processed items, which transactions hold',
    () async {
      final confirmed = await photo();
      await insertItem(
        'old-processed',
        status: 'processed',
        createdAt: old,
        attachments: [confirmed],
      );

      await env.service.purgeOld(now: now);

      expect(await remainingIds(), isEmpty);
      expect(File(confirmed).existsSync(), isTrue);
    },
  );

  test('keeps everything younger than 30 days', () async {
    final discarded = await photo();
    await insertItem(
      'recent-discarded',
      status: 'discarded',
      createdAt: recent,
      attachments: [discarded],
    );

    final purged = await env.service.purgeOld(now: now);

    expect(purged, 0);
    expect(await remainingIds(), {'recent-discarded'});
    expect(File(discarded).existsSync(), isTrue);
  });

  test('a photo already missing does not stop the purge', () async {
    await insertItem(
      'old-discarded',
      status: 'discarded',
      createdAt: old,
      attachments: ['${receipts.path}/${const Uuid().v4()}.jpg'],
    );

    final purged = await env.service.purgeOld(now: now);

    expect(purged, 1);
    expect(await remainingIds(), isEmpty);
  });

  test(
    'a partial confirmation, a discard and a purge keep the linked photo',
    () async {
      final linked = await photo();
      final id = await env.service.addItem(
        draft(
          [row(), row(title: 'sin cuenta', accountId: null)],
          attachments: [linked],
        ),
      );

      final result = await env.service.confirm(
        id,
        (await env.service.getItem(id))!.proposals,
      );
      expect(result.createdIds, hasLength(1));
      expect(result.errors, hasLength(1));
      await env.service.discard(id);

      final purged = await env.service.purgeOld(
        now: DateTime.now().add(const Duration(days: 31)),
      );

      expect(purged, 1);
      expect(await remainingIds(), isEmpty);
      expect(File(linked).existsSync(), isTrue);
      final attachments = await env.db
          .select(env.db.transactionAttachments)
          .get();
      expect(attachments.single.filePath, linked);
    },
  );

  test('never deletes a photo that a transaction refers to', () async {
    final linked = await photo();
    await insertItem(
      'old-discarded',
      status: 'discarded',
      createdAt: old,
      attachments: [linked],
    );
    await env.db
        .into(env.db.transactionAttachments)
        .insert(
          TransactionAttachmentInDB(
            id: 'att-1',
            transactionID: 'tx-1',
            filePath: linked,
            createdAt: old,
          ),
        );

    await env.service.purgeOld(now: now);

    expect(File(linked).existsSync(), isTrue);
  });

  test('never deletes a file outside the receipts folder', () async {
    final outside = await photo(dir: elsewhere);
    final traversal =
        '${receipts.path}/../elsewhere/${outside.split(RegExp(r'[\\/]')).last}';
    await insertItem(
      'old-discarded',
      status: 'discarded',
      createdAt: old,
      attachments: [outside, traversal],
    );

    final purged = await env.service.purgeOld(now: now);

    expect(purged, 1);
    expect(File(outside).existsSync(), isTrue);
  });

  test('never deletes a file whose name is not a receipt name', () async {
    final strange = await photo(name: 'notes.txt');
    final wrongExtension = await photo(name: '${const Uuid().v4()}.gif');
    await insertItem(
      'old-discarded',
      status: 'discarded',
      createdAt: old,
      attachments: [strange, wrongExtension],
    );

    await env.service.purgeOld(now: now);

    expect(File(strange).existsSync(), isTrue);
    expect(File(wrongExtension).existsSync(), isTrue);
  });

  test(
    'damaged attachments do not stop the purge of the other items',
    () async {
      final discarded = await photo();
      await env.db
          .into(env.db.aiInboxItems)
          .insert(
            AiInboxItemsCompanion.insert(
              id: 'broken',
              source: InboxSource.receipt.name,
              sourceRef: 'recibo-broken.jpg',
              createdAt: old,
              proposalsJson: '[]',
              status: const Value('discarded'),
              attachmentsJson: const Value('{not json'),
            ),
          );
      await insertItem(
        'old-discarded',
        status: 'discarded',
        createdAt: old,
        attachments: [discarded],
      );

      final purged = await env.service.purgeOld(now: now);

      expect(purged, 2);
      expect(File(discarded).existsSync(), isFalse);
    },
  );
}
