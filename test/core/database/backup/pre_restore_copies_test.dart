import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:sqlite3/sqlite3.dart';

const _tables = {'appData', 'accounts', 'transactions'};

void main() {
  late Directory dir;
  late String dbPath;
  late PreCopiesState state;
  final start = DateTime(2026, 11, 4, 9);

  File restoreCopy() => File(preCopyPath(dbPath, kPreRestoreCopyKind));
  File importCopy() => File(preCopyPath(dbPath, kPreImportCopyKind));

  Future<void> writeCopies() async {
    await restoreCopy().writeAsBytes([0]);
    await importCopy().writeAsBytes([0]);
    await state.markCopyKept(start);
  }

  /// A database like the app's, but with only [tables].
  Database makeDb({Set<String> tables = _tables, int userVersion = 15}) {
    final db = sqlite3.openInMemory();
    for (final table in tables) {
      db.execute('CREATE TABLE $table (id TEXT)');
    }
    db.execute('PRAGMA user_version = $userVersion');
    return db;
  }

  SqlQuery queryOf(Database db) =>
      (sql) async => [
        for (final row in db.select(sql)) {...row},
      ];

  Future<void> check(Database db, {Set<String> required = _tables}) =>
      checkDatabaseHealth(
        queryOf(db),
        userVersion: 15,
        requiredTables: required,
      );

  Future<PreCopiesOutcome> clean(Database db, DateTime now) => cleanPreCopies(
    dbPath: dbPath,
    state: state,
    now: now,
    check: () => check(db),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pre_copies');
    dbPath = '${dir.path}/monekin.db';
    await File(dbPath).writeAsBytes([0]);
    state = PreCopiesState(() async => File('${dir.path}/state.json'));
  });

  tearDown(() => dir.delete(recursive: true));

  group('checkDatabaseHealth', () {
    test('accepts a healthy database', () async {
      await check(makeDb());
    });

    test('rejects a database with appData but no transactions table', () async {
      final db = makeDb(tables: {'appData', 'accounts'});

      await expectLater(check(db), throwsStateError);
    });

    test('rejects an unexpected user_version', () async {
      final db = makeDb(userVersion: 14);

      await expectLater(check(db), throwsStateError);
    });

    test('rejects a failed integrity check', () async {
      await expectLater(
        checkDatabaseHealth(
          (sql) async => [
            {'integrity_check': 'row 3 missing from index'},
          ],
          userVersion: 15,
          requiredTables: _tables,
        ),
        throwsStateError,
      );
    });

    test('rejects a table the real query cannot read', () async {
      final db = makeDb(tables: {'appData', 'accounts', 'transactions'});
      db.execute('DROP TABLE accounts');

      await expectLater(
        checkDatabaseHealth(
          queryOf(db),
          userVersion: 15,
          requiredTables: {'appData', 'transactions'},
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('cleanPreCopies', () {
    test('keeps the copies before 7 days or 3 good starts', () async {
      await writeCopies();
      final db = makeDb();

      expect(
        await clean(db, start.add(const Duration(hours: 1))),
        PreCopiesOutcome.kept,
      );
      expect(
        await clean(db, start.add(const Duration(days: 1))),
        PreCopiesOutcome.kept,
      );

      expect(restoreCopy().existsSync(), isTrue);
      expect(importCopy().existsSync(), isTrue);
    });

    test('deletes them at the third good start', () async {
      await writeCopies();
      final db = makeDb();

      await clean(db, start.add(const Duration(hours: 1)));
      await clean(db, start.add(const Duration(hours: 2)));
      final outcome = await clean(db, start.add(const Duration(hours: 3)));

      expect(outcome, PreCopiesOutcome.deleted);
      expect(restoreCopy().existsSync(), isFalse);
      expect(importCopy().existsSync(), isFalse);
      expect(File(dbPath).existsSync(), isTrue);
    });

    test('deletes them at the first good start after 7 days', () async {
      await writeCopies();

      final outcome = await clean(makeDb(), start.add(const Duration(days: 7)));

      expect(outcome, PreCopiesOutcome.deleted);
      expect(restoreCopy().existsSync(), isFalse);
    });

    test('keeps them after 8 days when transactions is missing', () async {
      await writeCopies();
      final broken = makeDb(tables: {'appData', 'accounts'});

      final outcome = await clean(broken, start.add(const Duration(days: 8)));

      expect(outcome, PreCopiesOutcome.failedCheck);
      expect(restoreCopy().existsSync(), isTrue);
      expect(importCopy().existsSync(), isTrue);
      expect(await state.hasWarning(), isTrue);
    });

    test('a failed check does not count as a good start', () async {
      await writeCopies();
      final broken = makeDb(tables: {'appData', 'accounts'});

      await clean(broken, start.add(const Duration(hours: 1)));
      await clean(broken, start.add(const Duration(hours: 2)));
      await clean(broken, start.add(const Duration(hours: 3)));
      final outcome = await clean(
        makeDb(),
        start.add(const Duration(hours: 4)),
      );

      expect(outcome, PreCopiesOutcome.kept);
      expect(restoreCopy().existsSync(), isTrue);
    });

    test('the warning goes away once the check passes again', () async {
      await writeCopies();
      await clean(
        makeDb(tables: {'appData'}),
        start.add(const Duration(hours: 1)),
      );
      expect(await state.hasWarning(), isTrue);

      await clean(makeDb(), start.add(const Duration(hours: 2)));

      expect(await state.hasWarning(), isFalse);
    });

    test(
      'copies without a record start waiting from the first check',
      () async {
        await restoreCopy().writeAsBytes([0]);
        final db = makeDb();

        final first = await clean(db, start);
        final later = await clean(db, start.add(const Duration(days: 7)));

        expect(first, PreCopiesOutcome.kept);
        expect(later, PreCopiesOutcome.deleted);
      },
    );

    test('a new copy makes the waiting start again', () async {
      await writeCopies();
      final db = makeDb();
      await clean(db, start.add(const Duration(hours: 1)));
      await clean(db, start.add(const Duration(hours: 2)));

      await state.markCopyKept(start.add(const Duration(hours: 3)));
      final outcome = await clean(db, start.add(const Duration(hours: 4)));

      expect(outcome, PreCopiesOutcome.kept);
      expect(restoreCopy().existsSync(), isTrue);
    });

    test('with no copies it does nothing', () async {
      final outcome = await clean(makeDb(), start);

      expect(outcome, PreCopiesOutcome.noCopies);
      expect(File(dbPath).existsSync(), isTrue);
    });
  });
}
