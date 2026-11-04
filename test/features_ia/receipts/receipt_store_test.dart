import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/receipts/receipt_store.dart';

import '../privacy/jpeg_fixture.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('receipt_store_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'saveReceiptPhoto copies the photo to finanzas_ia/receipts/<uuid>.jpg',
    () async {
      final source = File('${tmp.path}/shot.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

      final saved = await saveReceiptPhoto(source, baseDir: tmp);

      expect(
        saved.path,
        startsWith(
          '${tmp.path}${Platform.pathSeparator}finanzas_ia${Platform.pathSeparator}receipts',
        ),
      );
      expect(RegExp(r'^[0-9a-f-]{36}\.jpg$').hasMatch(saved.fileName), isTrue);
      expect(File(saved.path).readAsBytesSync(), [0xFF, 0xD8, 0xFF, 0xD9]);
      expect(saved.bytes, [0xFF, 0xD8, 0xFF, 0xD9]);
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
        expect(latin1.decode(bytes), contains('JFIF'));
      }
      expect(saved.bytes, onDisk);
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
