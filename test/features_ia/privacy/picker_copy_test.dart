// Temporary copies left by the pickers are deleted only inside the app cache.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/privacy/picker_copy.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory cache;
  late Directory documents;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('picker-copy');
    cache = await Directory(p.join(root.path, 'cache')).create();
    documents = await Directory(p.join(root.path, 'documents')).create();
  });
  tearDown(() => root.delete(recursive: true));

  Future<File> write(Directory dir, String name) async =>
      File(p.join(dir.path, name)).writeAsString('data');

  test('a copy inside the cache is deleted', () async {
    final copy = await write(cache, 'image_picker1.jpg');

    expect(await deletePickerCopy(copy.path, cacheDir: cache), isTrue);
    expect(copy.existsSync(), isFalse);
  });

  test('a copy in a subfolder of the cache is deleted', () async {
    final folder = await Directory(p.join(cache.path, 'file_picker')).create();
    final copy = await write(folder, 'statement.pdf');

    expect(await deletePickerCopy(copy.path, cacheDir: cache), isTrue);
    expect(copy.existsSync(), isFalse);
  });

  test('a file outside the cache is kept', () async {
    final saved = await write(documents, 'receipt.jpg');

    expect(await deletePickerCopy(saved.path, cacheDir: cache), isFalse);
    expect(saved.existsSync(), isTrue);
  });

  test('a path that climbs out of the cache is kept', () async {
    final saved = await write(documents, 'receipt.jpg');
    final sneaky = p.join(cache.path, '..', 'documents', 'receipt.jpg');

    expect(await deletePickerCopy(sneaky, cacheDir: cache), isFalse);
    expect(saved.existsSync(), isTrue);
  });

  test('a folder next to the cache with the same prefix is kept', () async {
    final sibling = await Directory(p.join(root.path, 'cache2')).create();
    final other = await write(sibling, 'x.jpg');

    expect(await deletePickerCopy(other.path, cacheDir: cache), isFalse);
    expect(other.existsSync(), isTrue);
  });

  test('missing, empty and null paths do nothing', () async {
    expect(await deletePickerCopy(null, cacheDir: cache), isFalse);
    expect(await deletePickerCopy('', cacheDir: cache), isFalse);
    expect(
      await deletePickerCopy(p.join(cache.path, 'gone.jpg'), cacheDir: cache),
      isFalse,
    );
  });
}
