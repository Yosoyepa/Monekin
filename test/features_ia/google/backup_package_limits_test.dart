import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_package.dart';

const _mb = 1024 * 1024;

/// An entry that declares [size] bytes but holds only a few: a limit must reject
/// it from its declared size, before anything is extracted.
ArchiveFile _declared(String name, int size) => ArchiveFile.file(
  name,
  size,
  FileContentMemory(Uint8List.fromList([1, 2, 3])),
);

Uint8List _zip(Iterable<ArchiveFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.add(file);
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test('rejects an entry that declares 300 MB, before extracting it', () {
    final zip = _zip([_declared('receipts/huge.jpg', 300 * _mb)]);

    expect(
      () => parseBackupPackage(zip),
      throwsA(
        isA<InvalidBackupException>().having(
          (e) => e.detail,
          'detail',
          contains('receipts/huge.jpg'),
        ),
      ),
    );
  });

  test('rejects entries that together declare more than 512 MB', () {
    final zip = _zip([
      _declared('receipts/a.jpg', 200 * _mb),
      _declared('receipts/b.jpg', 200 * _mb),
      _declared('receipts/c.jpg', 200 * _mb),
    ]);

    expect(
      () => parseBackupPackage(zip),
      throwsA(
        isA<InvalidBackupException>().having(
          (e) => e.detail,
          'detail',
          contains('total'),
        ),
      ),
    );
  });

  test('rejects more than 5000 entries', () {
    final zip = _zip([
      for (var i = 0; i <= 5000; i++) ArchiveFile.string('receipts/$i.txt', ''),
    ]);

    expect(
      () => parseBackupPackage(zip),
      throwsA(
        isA<InvalidBackupException>().having(
          (e) => e.detail,
          'detail',
          contains('entries'),
        ),
      ),
    );
  });

  test('accepts exactly 5000 entries and goes on to read the package', () {
    final zip = _zip([
      for (var i = 0; i < 5000; i++) ArchiveFile.string('receipts/$i.txt', ''),
    ]);

    expect(
      () => parseBackupPackage(zip),
      throwsA(
        isA<InvalidBackupException>().having(
          (e) => e.detail,
          'detail',
          contains('no manifest'),
        ),
      ),
    );
  });
}
