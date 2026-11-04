import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';

import 'inbox_test_helpers.dart';

void main() {
  final now = DateTime(2026, 11, 4, 12);
  final old = now.subtract(const Duration(days: 31));
  final recent = now.subtract(const Duration(days: 29));

  late InboxTestEnv env;
  late Directory photos;

  setUp(() async {
    env = await InboxTestEnv.create();
    photos = await Directory.systemTemp.createTemp('inbox_purge');
  });

  tearDown(() async {
    await env.close();
    await photos.delete(recursive: true);
  });

  Future<String> photo(String name) async {
    final file = File('${photos.path}/$name');
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
    final discarded = await photo('discarded.jpg');
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
      final confirmed = await photo('confirmed.jpg');
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
    final discarded = await photo('recent-discarded.jpg');
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
      attachments: ['${photos.path}/gone.jpg'],
    );

    final purged = await env.service.purgeOld(now: now);

    expect(purged, 1);
    expect(await remainingIds(), isEmpty);
  });
}
