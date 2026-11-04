// F-09: photos lose their metadata before they are stored or sent.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/privacy/image_metadata.dart';
import 'jpeg_fixture.dart';

List<int> _markers(Uint8List jpeg) {
  final found = <int>[];
  var i = 2;
  while (i + 1 < jpeg.length) {
    final marker = jpeg[i + 1];
    found.add(marker);
    if (marker == 0xD9) break;
    final length = (jpeg[i + 2] << 8) | jpeg[i + 3];
    i += 2 + length;
    if (marker == 0xDA) {
      while (!(jpeg[i] == 0xFF &&
          jpeg[i + 1] != 0 &&
          !(jpeg[i + 1] >= 0xD0 && jpeg[i + 1] <= 0xD7))) {
        i++;
      }
    }
  }
  return found;
}

String _text(Uint8List bytes) => latin1.decode(bytes);

void main() {
  group('JPEG', () {
    test('Exif, GPS, XMP, IPTC, comment and trailer are removed', () {
      final stripped = stripImageMetadata(jpegWithMetadata());

      expect(_text(stripped), isNot(contains('Exif')));
      expect(_text(stripped), isNot(contains('GPS')));
      expect(_text(stripped), isNot(contains('xmpmeta')));
      expect(_text(stripped), isNot(contains('IPTC')));
      expect(_text(stripped), isNot(contains('camera')));
      expect(_markers(stripped), [0xE0, 0xDB, 0xC0, 0xDA, 0xD9]);
      expect(stripped.sublist(0, 2), [0xFF, 0xD8]);
      expect(stripped.sublist(stripped.length - 2), [0xFF, 0xD9]);
    });

    test('the image segments and the scan data are kept byte for byte', () {
      final original = jpegWithMetadata();
      final stripped = stripImageMetadata(original);

      expect(
        _text(stripped),
        contains(_text(Uint8List.fromList(jpegScanData))),
      );
      expect(_text(stripped), contains('JFIF'));
      expect(
        _text(stripped),
        contains(_text(jpegSegment(0xDB, List.filled(65, 7)))),
      );
    });

    test('only APP0, APP2 and APP14 stay among the APPn segments', () {
      final jpeg = Uint8List.fromList([
        0xFF,
        0xD8,
        ...jpegSegment(0xE0, ascii.encode('JFIF\u0000\u0001\u0001')),
        ...jpegSegment(0xE1, ascii.encode('Exif GPS one')),
        ...jpegSegment(0xE2, ascii.encode('ICC_PROFILE\u0000profile')),
        ...jpegSegment(0xE3, ascii.encode('meta three')),
        ...jpegSegment(0xE4, ascii.encode('meta four')),
        ...jpegSegment(0xEC, ascii.encode('ducky twelve')),
        ...jpegSegment(0xED, ascii.encode('Photoshop 3.0 IPTC')),
        ...jpegSegment(0xEE, ascii.encode('Adobe\u0000\u0064')),
        ...jpegSegment(0xEF, ascii.encode('meta fifteen')),
        ...jpegSegment(0xFE, ascii.encode('a comment')),
        ...jpegSegment(0xDB, List.filled(65, 7)),
        ...jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]),
        1,
        2,
        0xFF,
        0xD9,
      ]);

      final stripped = stripImageMetadata(jpeg);

      expect(_markers(stripped), [0xE0, 0xE2, 0xEE, 0xDB, 0xDA, 0xD9]);
      for (final secret in ['GPS', 'meta', 'IPTC', 'ducky', 'comment']) {
        expect(_text(stripped), isNot(contains(secret)), reason: secret);
      }
      expect(_text(stripped), contains('ICC_PROFILE'));
      expect(_text(stripped), contains('Adobe'));
    });

    test('stripping twice changes nothing', () {
      final once = stripImageMetadata(jpegWithMetadata());
      expect(stripImageMetadata(once), once);
    });

    test('a truncated segment ends the image instead of being copied', () {
      final original = jpegWithMetadata();
      final cut = Uint8List.sublistView(original, 0, 40);

      final stripped = stripImageMetadata(cut);

      expect(_text(stripped), isNot(contains('Exif')));
      expect(stripped.length, lessThan(cut.length));
    });

    test('a JPEG with no metadata is unchanged', () {
      final clean = Uint8List.fromList([
        0xFF,
        0xD8,
        ...jpegSegment(0xDB, List.filled(65, 3)),
        ...jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]),
        1,
        2,
        3,
        0xFF,
        0xD9,
      ]);
      expect(stripImageMetadata(clean), clean);
    });

    for (final name in [
      'exito_01.jpg',
      'e2e_01_supermercado.jpg',
      'e2e_02_drogueria.jpg',
      'e2e_03_restaurante.jpg',
      'blind3_farmacia.jpg',
      'blind3_panaderia.jpg',
    ]) {
      test('fixture $name keeps its image data', () {
        final bytes = File(
          'test/features_ia/fixtures/receipts/$name',
        ).readAsBytesSync();
        final stripped = stripImageMetadata(bytes);

        expect(stripped.length, lessThanOrEqualTo(bytes.length));
        expect(stripped.sublist(0, 2), [0xFF, 0xD8]);
        expect(stripped.sublist(stripped.length - 2), [0xFF, 0xD9]);
        expect(_markers(stripped), isNot(contains(0xE1)));
        expect(_markers(stripped), isNot(contains(0xED)));
        expect(_markers(stripped), isNot(contains(0xFE)));
        expect(_markers(stripped), contains(0xDA));
        expect(stripImageMetadata(stripped), stripped);
      });
    }
  });

  group('PNG', () {
    Uint8List chunk(String type, List<int> data) {
      final length = data.length;
      return Uint8List.fromList([
        length >> 24 & 0xFF,
        length >> 16 & 0xFF,
        length >> 8 & 0xFF,
        length & 0xFF,
        ...ascii.encode(type),
        ...data,
        0,
        0,
        0,
        0,
      ]);
    }

    final signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    test('tEXt, iTXt, zTXt and eXIf chunks are removed', () {
      final png = Uint8List.fromList([
        ...signature,
        ...chunk('IHDR', List.filled(13, 1)),
        ...chunk('tEXt', ascii.encode('Author\u0000Juan')),
        ...chunk('iTXt', ascii.encode('XML:com.adobe.xmp\u0000<x/>')),
        ...chunk('zTXt', ascii.encode('Comment\u0000\u0000zz')),
        ...chunk('eXIf', [...ascii.encode('Exif'), 0, 0, 1, 2]),
        ...chunk('IDAT', [9, 8, 7]),
        ...chunk('IEND', []),
        ...ascii.encode('trailing Exif'),
      ]);

      final stripped = stripImageMetadata(png);

      expect(
        stripped,
        Uint8List.fromList([
          ...signature,
          ...chunk('IHDR', List.filled(13, 1)),
          ...chunk('IDAT', [9, 8, 7]),
          ...chunk('IEND', []),
        ]),
      );
      expect(_text(stripped), isNot(contains('Exif')));
    });

    test('a damaged chunk length ends the image', () {
      final png = Uint8List.fromList([
        ...signature,
        ...chunk('IHDR', List.filled(13, 1)),
        0x7F,
        0xFF,
        0xFF,
        0xFF,
        ...ascii.encode('tEXtsecret'),
      ]);

      final stripped = stripImageMetadata(png);

      expect(_text(stripped), isNot(contains('secret')));
    });
  });

  test('other formats are rejected, never returned as they are', () {
    for (final bytes in [
      Uint8List.fromList(ascii.encode('not an image')),
      Uint8List.fromList(
        ascii.encode('RIFF\u0000\u0000\u0000\u0000WEBPEXIF secret'),
      ),
      Uint8List(0),
    ]) {
      expect(
        () => stripImageMetadata(bytes),
        throwsA(isA<UnsupportedImageException>()),
      );
    }
  });
}
