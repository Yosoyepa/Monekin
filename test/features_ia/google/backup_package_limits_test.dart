import 'dart:convert';
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

  group('the directory is vetted before ZipDecoder runs', () {
    late bool decoded;

    setUp(() => decoded = false);

    Archive spy(Uint8List bytes) {
      decoded = true;
      return Archive();
    }

    void expectRejected(Uint8List zip, Matcher detail) {
      expect(
        () => parseBackupPackage(zip, decode: spy),
        throwsA(
          isA<InvalidBackupException>().having(
            (e) => e.detail,
            'detail',
            detail,
          ),
        ),
      );
      expect(decoded, isFalse);
    }

    test('an entry declared as 1 GB', () {
      expectRejected(
        _zip([_declared('receipts/huge.jpg', 1024 * _mb)]),
        contains('receipts/huge.jpg'),
      );
    });

    test('a symbolic link', () {
      expectRejected(
        _zip([ArchiveFile.symlink('receipts/link.jpg', '/etc/passwd')]),
        contains('symbolic link'),
      );
    });

    for (final name in [
      r'receipts\..\x.jpg',
      r'..\x',
      '../x.jpg',
      'receipts/../../x.jpg',
      'C:/x.jpg',
      'C:',
      '/abs/x.jpg',
    ]) {
      test('the name $name', () {
        expectRejected(
          _zip([ArchiveFile.string(name, 'x')]),
          contains('unsafe entry name'),
        );
      });
    }

    test('a repeated name', () {
      // Archive keeps one entry per name, so write b.jpg and rename it to a.jpg
      // in the bytes (same length, local header and directory alike).
      final zip = _zip([
        ArchiveFile.string('receipts/a.jpg', '1'),
        ArchiveFile.string('receipts/b.jpg', '2'),
      ]);
      final b = ascii.encode('receipts/b.jpg');
      for (var i = 0; i + b.length <= zip.length; i++) {
        if (List.generate(b.length, (j) => zip[i + j]).join(',') ==
            b.join(',')) {
          zip.setRange(i, i + b.length, ascii.encode('receipts/a.jpg'));
        }
      }

      expectRejected(zip, contains('repeated'));
    });

    test('a package without a zip directory', () {
      final zip = _zip([ArchiveFile.string('manifest.json', '{}')]);

      expectRejected(
        Uint8List.sublistView(zip, 0, zip.length - 30),
        contains('directory'),
      );
    });

    test('a good package is decoded once, after the directory', () {
      final zip = _zip([ArchiveFile.string('manifest.json', '{}')]);

      expect(
        () => parseBackupPackage(zip, decode: spy),
        throwsA(isA<InvalidBackupException>()),
      );
      expect(decoded, isTrue);
    });
  });

  test('a download over the limit stops before it is kept', () async {
    Stream<List<int>> chunks() async* {
      yield Uint8List(60);
      yield Uint8List(60);
      fail('the third chunk must never be asked for');
    }

    await expectLater(
      collectCapped(chunks(), maxBytes: 100),
      throwsA(isA<InvalidBackupException>()),
    );
    expect(
      await collectCapped(Stream.value(Uint8List(100)), maxBytes: 100),
      hasLength(100),
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
