import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:sqlite3/sqlite3.dart';

const newTables = ['ai_notice_claims'];

/// Copies the v15 sample and applies `assets/sql/migrations/v16.sql` the way `AppDB.migrateDB` does
/// (statement split, FK pragmas stripped, FK off during the batch). Returns the open DB.
Database migrateSample() {
  final tmp = File(
    '${Directory.systemTemp.path}/v15_sample_claims_migtest_'
    '${DateTime.now().microsecondsSinceEpoch}.db',
  );
  File('assets/sql/samples/v15_sample.db').copySync(tmp.path);
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync();
  });

  final db = sqlite3.open(tmp.path);
  addTearDown(db.close);

  final statements =
      splitSQLStatements(
        File('assets/sql/migrations/v16.sql').readAsStringSync(),
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

Set<String> tablesOf(Database db) => db
    .select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    )
    .map((r) => r['name'] as String)
    .toSet();

int count(Database db, String table) =>
    db.select('SELECT COUNT(*) c FROM $table').first['c'] as int;

void main() {
  test('the schema version is 16', () {
    final app = AppDB.forTesting(NativeDatabase.memory());
    addTearDown(app.close);

    expect(app.schemaVersion, 16);
  });

  test(
    'a v15 database migrates without losing data and gains the claims table',
    () {
      final before = sqlite3.open('assets/sql/samples/v15_sample.db');
      addTearDown(before.close);
      final tablesBefore = tablesOf(before);
      expect(tablesBefore.intersection(newTables.toSet()), isEmpty);

      final after = migrateSample();

      expect(tablesOf(after), {...tablesBefore, ...newTables});
      for (final table in tablesBefore) {
        expect(
          count(after, table),
          count(before, table),
          reason: 'rows of $table changed',
        );
      }
      expect(count(after, 'ai_notice_claims'), 0);
    },
  );

  test('the migrated table has the same columns as the drift schema', () {
    final app = AppDB.forTesting(NativeDatabase.memory());
    addTearDown(app.close);
    final migrated = migrateSample();

    final table = app.allTables.singleWhere(
      (t) => t.actualTableName == 'ai_notice_claims',
    );
    final columns = migrated
        .select('PRAGMA table_info(ai_notice_claims)')
        .map((r) => r['name'] as String)
        .toSet();

    expect(columns, table.$columns.map((c) => c.name).toSet());
  });

  test('the fingerprint is the primary key: a second insert is ignored', () {
    final db = migrateSample();

    db.execute(
      "INSERT OR IGNORE INTO ai_notice_claims (fingerprint, createdAt) VALUES ('a', '2026-11-04T10:00:00.000')",
    );
    db.execute(
      "INSERT OR IGNORE INTO ai_notice_claims (fingerprint, createdAt) VALUES ('a', '2026-11-04T10:00:02.000')",
    );

    expect(db.updatedRows, 0);
    expect(count(db, 'ai_notice_claims'), 1);
  });
}
