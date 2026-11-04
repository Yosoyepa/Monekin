import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/receipts/receipt_store.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('receipt_store_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'saveReceiptPhoto copies the photo to finanzas_ia/receipts/<uuid>.jpg',
    () async {
      final source = File('${tmp.path}/shot.jpg')
        ..writeAsBytesSync([1, 2, 3, 4]);

      final saved = await saveReceiptPhoto(source, baseDir: tmp);

      expect(
        saved.path,
        startsWith(
          '${tmp.path}${Platform.pathSeparator}finanzas_ia${Platform.pathSeparator}receipts',
        ),
      );
      expect(RegExp(r'^[0-9a-f-]{36}\.jpg$').hasMatch(saved.fileName), isTrue);
      expect(File(saved.path).readAsBytesSync(), [1, 2, 3, 4]);
      expect(saved.bytes, [1, 2, 3, 4]);
    },
  );
}
