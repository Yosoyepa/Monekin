// BUG-09: one bank notice read twice at the same time, also from another isolate, makes one inbox item.
import 'dart:io';
import 'dart:isolate';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/features_ia/inbox/drift_inbox_service.dart';
import 'package:monekin/features_ia/notifications/notice_claims.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';

import 'test_support.dart';

const _nequi = 'com.nequi.MobileApp';
final _now = DateTime(2026, 11, 4, 10, 16);

RawNotice _notice(String content, {int id = 7, int at = 0}) => RawNotice(
  package: _nequi,
  title: 'Nequi',
  content: content,
  postedAtMs: DateTime(2026, 11, 4, 10, 15).millisecondsSinceEpoch + at,
  id: id,
);

/// A processor over the database file [path]: its own connection, like the one of a background isolate.
Future<NoticeOutcome> _processOn(String path, RawNotice raw) async {
  final db = AppDB.forTesting(NativeDatabase(File(path)));
  try {
    final prefs = NotificationsPrefs(MemoryKeyValueStore());
    return await NotificationProcessor(
      prefs: prefs,
      notifier: FakeNotifier(),
      inbox: () => DriftInboxService(
        db: db,
        transactions: TransactionService.forTesting(db),
      ),
      claims: () => DriftNoticeClaims(db),
      aiConfigured: () async => false,
      accountForCard: (_) async => null,
      parseAmount: testAmountParser,
      now: () => _now,
    ).process(raw);
  } finally {
    await db.close();
  }
}

/// Same, from another isolate. Kept at top level so the closure carries nothing but its arguments.
Future<NoticeOutcome> _inIsolate(String path, RawNotice raw) =>
    Isolate.run(() => _processOn(path, raw));

void main() {
  late Directory dir;
  late String path;
  late AppDB db;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('finanzas_claims_');
    path = '${dir.path}${Platform.pathSeparator}claims.db';
    db = AppDB.forTesting(NativeDatabase(File(path)));
    // Creates the schema before any second connection opens the file.
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<int> items() async => (await db.select(db.aiInboxItems).get()).length;

  Future<int> claimRows() async =>
      (await db.select(db.aiNoticeClaims).get()).length;

  test('the first claim wins and the others see a duplicate', () async {
    final claims = DriftNoticeClaims(db);
    expect(await claims.claim('fp', _now), isTrue);
    expect(await claims.claim('fp', _now), isFalse);
    expect(await claims.claim('other', _now), isTrue);
    expect(await claimRows(), 2);
  });

  test('a released claim can be taken again', () async {
    final claims = DriftNoticeClaims(db);
    await claims.claim('fp', _now);
    await claims.release('fp');
    expect(await claims.claim('fp', _now), isTrue);
  });

  test('claims older than 30 days are purged', () async {
    final claims = DriftNoticeClaims(db);
    await claims.claim('old', _now.subtract(const Duration(days: 31)));
    await claims.claim('recent', _now.subtract(const Duration(days: 29)));

    expect(await claims.claim('new', _now), isTrue);

    final left = (await db.select(db.aiNoticeClaims).get())
        .map((c) => c.fingerprint)
        .toSet();
    expect(left, {'recent', 'new'});
    expect(await claims.claim('old', _now), isTrue);
    expect(await claims.claim('recent', _now), isFalse);
  });

  test(
    'many claims of one fingerprint at once give exactly one winner',
    () async {
      final claims = DriftNoticeClaims(db);
      final results = await Future.wait([
        for (var i = 0; i < 20; i++) claims.claim('fp', _now),
      ]);
      expect(results.where((won) => won), hasLength(1));
    },
  );

  test('two concurrent process calls of one notice create one item', () async {
    final results = await Future.wait([
      _processOn(path, _notice('Pagaste \$45.900 en EXITO')),
      _processOn(path, _notice('Pagaste \$45.900 en EXITO')),
    ]);

    expect(
      results,
      unorderedEquals([NoticeOutcome.recognized, NoticeOutcome.duplicate]),
    );
    expect(await items(), 1);
  });

  test(
    'the live listener and an isolate on the same notice create one item',
    () async {
      final results = await Future.wait([
        _processOn(path, _notice('Pagaste \$45.900 en EXITO')),
        _inIsolate(path, _notice('Pagaste \$45.900 en EXITO')),
        _inIsolate(path, _notice('Pagaste \$45.900 en EXITO')),
      ]);

      expect(results.where((o) => o == NoticeOutcome.recognized), hasLength(1));
      expect(results.where((o) => o == NoticeOutcome.duplicate), hasLength(2));
      expect(await items(), 1);
    },
  );

  test('two different notices create two items', () async {
    final results = await Future.wait([
      _processOn(path, _notice('Pagaste \$45.900 en EXITO', id: 7)),
      _inIsolate(path, _notice('Pagaste \$12.000 en D1', id: 8)),
    ]);

    expect(results, everyElement(NoticeOutcome.recognized));
    expect(await items(), 2);
  });
}
