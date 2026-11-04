import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/privacy/image_metadata.dart';
import 'package:monekin/features_ia/receipts/receipt_store.dart';

import '../privacy/jpeg_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('receipt_store_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'saveReceiptPhoto writes the photo to finanzas_ia/receipts/<uuid>.png',
    () async {
      final source = File('${tmp.path}/shot.jpg')
        ..writeAsBytesSync(minimalJpeg());

      final saved = await saveReceiptPhoto(source, baseDir: tmp);

      expect(
        saved.path,
        startsWith(
          '${tmp.path}${Platform.pathSeparator}finanzas_ia${Platform.pathSeparator}receipts',
        ),
      );
      expect(RegExp(r'^[0-9a-f-]{36}\.png$').hasMatch(saved.fileName), isTrue);
      expect(isReceiptFileName(saved.fileName), isTrue);
      expect(saved.bytes.sublist(0, 8), pngSignature);
      expect(File(saved.path).readAsBytesSync(), saved.bytes);
    },
  );

  test(
    'the stored photo and the bytes returned carry no Exif or GPS',
    () async {
      final source = File('${tmp.path}/shot.jpg')
        ..writeAsBytesSync(jpegWithMetadata());
      expect(latin1.decode(source.readAsBytesSync()), contains('Exif'));

      final saved = await saveReceiptPhoto(source, baseDir: tmp);

      final onDisk = File(saved.path).readAsBytesSync();
      for (final bytes in [onDisk, saved.bytes]) {
        expect(latin1.decode(bytes), isNot(contains('Exif')));
        expect(latin1.decode(bytes), isNot(contains('GPS')));
        expect(latin1.decode(bytes), isNot(contains('JFIF')));
      }
      expect(saved.bytes, onDisk);
    },
  );

  test('a PNG with data inside IDAT is saved without it', () async {
    final source = File('${tmp.path}/shot.png')
      ..writeAsBytesSync(pngWithDataInIdat());

    final saved = await saveReceiptPhoto(source, baseDir: tmp);

    expect(saved.path, endsWith('.png'));
    expect(isReceiptFileName(saved.fileName), isTrue);
    final onDisk = File(saved.path).readAsBytesSync();
    expect(latin1.decode(onDisk), isNot(contains('GPS-PRIVATE')));
    expect(latin1.decode(onDisk), isNot(contains('pHYs')));
  });

  test(
    'a GIF is converted to a PNG and saved with the png extension',
    () async {
      final gif = Uint8List.fromList([
        ...ascii.encode('GIF89a'),
        0x01,
        0x00,
        0x01,
        0x00,
        0x80,
        0x00,
        0x00,
        0xFF,
        0xFF,
        0xFF,
        0x00,
        0x00,
        0x00,
        0x21,
        0xF9,
        0x04,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x2C,
        0x00,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x01,
        0x00,
        0x00,
        0x02,
        0x02,
        0x44,
        0x01,
        0x00,
        0x3B,
      ]);
      final source = File('${tmp.path}/shot.gif')..writeAsBytesSync(gif);

      final saved = await saveReceiptPhoto(source, baseDir: tmp);

      expect(saved.path, endsWith('.png'));
      expect(isReceiptFileName(saved.fileName), isTrue);
      expect(saved.bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(File(saved.path).readAsBytesSync(), saved.bytes);
    },
  );

  test(
    'bytes that are not an image are rejected and nothing is stored',
    () async {
      final source = File('${tmp.path}/notes.txt')
        ..writeAsBytesSync(ascii.encode('not an image at all'));

      await expectLater(
        saveReceiptPhoto(source, baseDir: tmp),
        throwsA(isA<UnsupportedImageException>()),
      );

      expect(Directory('${tmp.path}/finanzas_ia').existsSync(), isFalse);
    },
  );

  test('deleteReceiptPhoto removes the file and ignores one already gone', () {
    final file = File('${tmp.path}/gone.jpg')..writeAsBytesSync([1]);
    final photo = SavedReceiptPhoto(
      path: file.path,
      bytes: Uint8List.fromList([1]),
    );

    deleteReceiptPhoto(photo);
    deleteReceiptPhoto(photo);

    expect(file.existsSync(), isFalse);
  });
}
