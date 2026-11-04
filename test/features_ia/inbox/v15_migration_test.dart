import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:sqlite3/sqlite3.dart';

const newTables = ['aiInboxItems', 'transactionAttachments'];

/// Copies the v14 sample, fills it with a transaction and applies
/// `assets/sql/migrations/v15.sql` the way `AppDB.migrateDB` does (statement
/// split, FK pragmas stripped, FK off during the batch). Returns the open DB.
Database migrateSample() {
  final tmp = File(
    '${Directory.systemTemp.path}/v14_sample_inbox_migtest_'
    '${DateTime.now().microsecondsSinceEpoch}.db',
  );
  File('assets/sql/samples/v14_sample.db').copySync(tmp.path);
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync();
  });

  final db = sqlite3.open(tmp.path);
  addTearDown(db.close);

  final statements =
      splitSQLStatements(
        File('assets/sql/migrations/v15.sql').readAsStringSync(),
      ).where(
        (s) => !RegExp(
          r'^\s*PRAGMA\s+foreign_keys',
          caseSensitive: false,
        ).hasMatch(s),
      );

  db.execute('PRAGMA foreign_keys = OFF');
  db.execute('BEGIN');
  for (final s in statements) {
    db.execute(s);
  }
  expect(db.select('PRAGMA foreign_key_check'), isEmpty);
  db.execute('COMMIT');
  db.execute('PRAGMA foreign_keys = ON');

  return db;
}

int count(Database db, String table) =>
    db.select('SELECT COUNT(*) c FROM $table').first['c'] as int;

void main() {
  test('the schema version is 15', () {
    final app = AppDB.forTesting(NativeDatabase.memory());
    addTearDown(app.close);

    expect(app.schemaVersion, 15);
  });

  test('a v14 database migrates without losing data and gains the new tables', () {
    final before = sqlite3.open('assets/sql/samples/v14_sample.db');
    addTearDown(before.close);

    final tablesBefore = before
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        )
        .map((r) => r['name'] as String)
        .toSet();
    expect(tablesBefore.intersection(newTables.toSet()), isEmpty);

    final after = migrateSample();

    final tablesAfter = after
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        )
        .map((r) => r['name'] as String)
        .toSet();
    expect(tablesAfter, {...tablesBefore, ...newTables});

    for (final table in tablesBefore) {
      expect(
        count(after, table),
        count(before, table),
        reason: 'rows of $table changed',
      );
    }

    expect(count(after, 'aiInboxItems'), 0);
    expect(count(after, 'transactionAttachments'), 0);
  });

  test('the migrated tables have the same columns as the drift schema', () {
    final app = AppDB.forTesting(NativeDatabase.memory());
    addTearDown(app.close);

    final migrated = migrateSample();

    for (final table in app.allTables.where(
      (t) => newTables.contains(t.actualTableName),
    )) {
      final columns = migrated
          .select('PRAGMA table_info(${table.actualTableName})')
          .map((r) => r['name'] as String)
          .toSet();

      expect(
        columns,
        table.$columns.map((c) => c.name).toSet(),
        reason: table.actualTableName,
      );
    }
  });

  test('deleting a transaction deletes its attachments', () {
    final db = migrateSample();

    final tx = db.select('SELECT id FROM transactions LIMIT 1');
    expect(tx, isNotEmpty, reason: 'the sample should carry transactions');
    final id = tx.first['id'] as String;

    db.execute(
      "INSERT INTO transactionAttachments (id, transactionID, filePath, createdAt) VALUES ('att-1', ?, '/tmp/a.jpg', '2026-11-04T10:00:00.000')",
      [id],
    );
    expect(count(db, 'transactionAttachments'), 1);

    db.execute('DELETE FROM transactions WHERE id = ?', [id]);
    expect(count(db, 'transactionAttachments'), 0);
  });

  test('the item status only accepts the contract values', () {
    final db = migrateSample();

    expect(
      () => db.execute(
        "INSERT INTO aiInboxItems (id, source, sourceRef, status, createdAt, proposalsJson) VALUES ('x', 'receipt', 'a.jpg', 'bogus', '2026-11-04', '[]')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}
