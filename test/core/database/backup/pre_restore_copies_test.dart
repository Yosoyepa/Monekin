import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';

void main() {
  late Directory dir;
  late String dbPath;

  Future<void> writeCopies() async {
    await File(preCopyPath(dbPath, kPreRestoreCopyKind)).writeAsBytes([0]);
    await File(preCopyPath(dbPath, kPreImportCopyKind)).writeAsBytes([0]);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pre_copies');
    dbPath = '${dir.path}/monekin.db';
    await File(dbPath).writeAsBytes([0]);
  });

  tearDown(() => dir.delete(recursive: true));

  test('deletes both copies once the database answers a query', () async {
    await writeCopies();

    await deletePreCopiesIfOpens(dbPath: dbPath, probe: () async {});

    expect(
      File(preCopyPath(dbPath, kPreRestoreCopyKind)).existsSync(),
      isFalse,
    );
    expect(File(preCopyPath(dbPath, kPreImportCopyKind)).existsSync(), isFalse);
    expect(File(dbPath).existsSync(), isTrue);
  });

  test('keeps the copies when the database does not open', () async {
    await writeCopies();

    await expectLater(
      deletePreCopiesIfOpens(
        dbPath: dbPath,
        probe: () async => throw Exception('database is locked'),
      ),
      throwsException,
    );

    expect(File(preCopyPath(dbPath, kPreRestoreCopyKind)).existsSync(), isTrue);
    expect(File(preCopyPath(dbPath, kPreImportCopyKind)).existsSync(), isTrue);
  });

  test('succeeds when there are no copies to delete', () async {
    await deletePreCopiesIfOpens(dbPath: dbPath, probe: () async {});

    expect(File(dbPath).existsSync(), isTrue);
  });
}
