// F-09: photos are rebuilt from a list of what is allowed before they are stored or sent.
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

    test('the JFIF header is made again, with no thumbnail', () {
      final stripped = stripImageMetadata(jpegWithMetadata());

      expect(stripped.sublist(2, 20), [
        0xFF, 0xE0, 0x00, 0x10, //
        0x4A, 0x46, 0x49, 0x46, 0x00, //
        0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, //
      ]);
    });

    test('the image segments and the scan data are kept byte for byte', () {
      final original = jpegWithMetadata();
      final stripped = stripImageMetadata(original);

      expect(
        _text(stripped),
        contains(_text(Uint8List.fromList(jpegScanData))),
      );
      expect(
        _text(stripped),
        contains(_text(jpegSegment(0xDB, List.filled(65, 7)))),
      );
      expect(
        _text(stripped),
        contains(_text(jpegSegment(0xC0, [8, 0, 2, 0, 2, 1, 1, 0x11, 0]))),
      );
    });

    test('APP1, APP2, APP3, APP13, APP14 and COM leave no marker behind', () {
      final jpeg = Uint8List.fromList([
        0xFF,
        0xD8,
        ...jpegSegment(0xE0, ascii.encode('JFIF\u0000\u0001\u0001thumb')),
        ...jpegSegment(0xE1, ascii.encode('Exif GPS-SYNTHETIC one')),
        ...jpegSegment(0xE2, ascii.encode('GPS-SYNTHETIC ICC_PROFILE')),
        ...jpegSegment(0xE3, ascii.encode('GPS-SYNTHETIC three')),
        ...jpegSegment(0xE4, ascii.encode('meta four')),
        ...jpegSegment(0xEC, ascii.encode('ducky twelve')),
        ...jpegSegment(0xED, ascii.encode('Photoshop 3.0 IPTC')),
        ...jpegSegment(0xEE, ascii.encode('GPS-SYNTHETIC fourteen')),
        ...jpegSegment(0xEF, ascii.encode('meta fifteen')),
        ...jpegSegment(0xFE, ascii.encode('a comment')),
        ...jpegSegment(0xDB, List.filled(65, 7)),
        ...jpegSegment(0xC0, [8, 0, 2, 0, 2, 1, 1, 0x11, 0]),
        ...jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]),
        1,
        2,
        0xFF,
        0xD9,
      ]);

      final stripped = stripImageMetadata(jpeg);

      expect(_markers(stripped), [0xE0, 0xDB, 0xC0, 0xDA, 0xD9]);
      for (final secret in [
        'GPS',
        'meta',
        'IPTC',
        'ducky',
        'comment',
        'ICC',
        'thumb',
      ]) {
        expect(_text(stripped), isNot(contains(secret)), reason: secret);
      }
    });

    test('an Adobe APP14 is made again with only the colour transform', () {
      final adobe = [
        ...ascii.encode('Adobe'),
        0x00, 0x64, 0x80, 0x00, 0xC0, 0x00, 0x02, //
        ...ascii.encode('GPS-SYNTHETIC trailing bytes'),
      ];
      final jpeg = Uint8List.fromList([
        0xFF,
        0xD8,
        ...jpegSegment(0xEE, adobe),
        ...jpegSegment(0xDB, List.filled(65, 7)),
        ...jpegSegment(0xC0, [8, 0, 2, 0, 2, 1, 1, 0x11, 0]),
        ...jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]),
        1,
        0xFF,
        0xD9,
      ]);

      final stripped = stripImageMetadata(jpeg);

      expect(_markers(stripped), [0xE0, 0xEE, 0xDB, 0xC0, 0xDA, 0xD9]);
      expect(_text(stripped), isNot(contains('GPS')));
      final at = _text(stripped).indexOf('Adobe');
      expect(stripped.sublist(at - 4, at + 12), [
        0xFF, 0xEE, 0x00, 0x0E, //
        ...ascii.encode('Adobe'),
        0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x02, //
      ]);
    });

    test('DQT, DHT, DRI, SOF and SOS stay, in the order they came', () {
      final jpeg = Uint8List.fromList([
        0xFF,
        0xD8,
        ...jpegSegment(0xE1, ascii.encode('Exif')),
        ...jpegSegment(0xDB, List.filled(65, 7)),
        ...jpegSegment(0xC0, [8, 0, 2, 0, 2, 1, 1, 0x11, 0]),
        ...jpegSegment(0xC4, List.filled(20, 9)),
        ...jpegSegment(0xDD, [0, 4]),
        ...jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]),
        1,
        0xFF,
        0xD9,
      ]);

      expect(_markers(stripImageMetadata(jpeg)), [
        0xE0,
        0xDB,
        0xC0,
        0xC4,
        0xDD,
        0xDA,
        0xD9,
      ]);
    });

    test('stripping twice changes nothing', () {
      final once = stripImageMetadata(jpegWithMetadata());
      expect(stripImageMetadata(once), once);
    });

    test('a file cut before the image data is rejected, not copied', () {
      final original = jpegWithMetadata();
      final cut = Uint8List.sublistView(original, 0, 40);

      expect(
        () => stripImageMetadata(cut),
        throwsA(isA<UnsupportedImageException>()),
      );
    });

    test('60 Mpx declared are rejected', () {
      final big = Uint8List.fromList([
        0xFF,
        0xD8,
        ...jpegSegment(0xDB, List.filled(65, 7)),
        // 10000 x 6000
        ...jpegSegment(0xC0, [8, 0x17, 0x70, 0x27, 0x10, 1, 1, 0x11, 0]),
        ...jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]),
        1,
        0xFF,
        0xD9,
      ]);

      expect(
        () => stripImageMetadata(big),
        throwsA(isA<UnsupportedImageException>()),
      );
    });

    test('over 25 MiB is rejected before it is read', () {
      final huge = Uint8List(25 * 1024 * 1024 + 1)
        ..setRange(0, 3, [0xFF, 0xD8, 0xFF]);

      expect(
        () => stripImageMetadata(huge),
        throwsA(isA<UnsupportedImageException>()),
      );
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
        expect(_markers(stripped), isNot(contains(0xE2)));
        expect(_markers(stripped), isNot(contains(0xEE)));
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

    List<int> ihdr(int width, int height) => [
      width >> 24 & 0xFF,
      width >> 16 & 0xFF,
      width >> 8 & 0xFF,
      width & 0xFF,
      height >> 24 & 0xFF,
      height >> 16 & 0xFF,
      height >> 8 & 0xFF,
      height & 0xFF,
      8, 2, 0, 0, 0, //
    ];

    test('only the allowed chunks stay', () {
      final png = Uint8List.fromList([
        ...signature,
        ...chunk('IHDR', ihdr(2, 2)),
        ...chunk('iCCP', ascii.encode('GPS-SYNTHETIC\u0000\u0000zz')),
        ...chunk('tEXt', ascii.encode('Author\u0000Juan')),
        ...chunk('iTXt', ascii.encode('XML:com.adobe.xmp\u0000<x/>')),
        ...chunk('zTXt', ascii.encode('Comment\u0000\u0000zz')),
        ...chunk('eXIf', [...ascii.encode('Exif'), 0, 0, 1, 2]),
        ...chunk('zzZz', ascii.encode('GPS-SYNTHETIC invented')),
        ...chunk('gAMA', [0, 1, 0, 0]),
        ...chunk('sRGB', [0]),
        ...chunk('pHYs', [0, 0, 0, 1, 0, 0, 0, 1, 1]),
        ...chunk('PLTE', [1, 2, 3]),
        ...chunk('tRNS', [255]),
        ...chunk('IDAT', [9, 8, 7]),
        ...chunk('IEND', []),
        ...ascii.encode('trailing Exif'),
      ]);

      final stripped = stripImageMetadata(png);

      expect(
        stripped,
        Uint8List.fromList([
          ...signature,
          ...chunk('IHDR', ihdr(2, 2)),
          ...chunk('gAMA', [0, 1, 0, 0]),
          ...chunk('sRGB', [0]),
          ...chunk('pHYs', [0, 0, 0, 1, 0, 0, 0, 1, 1]),
          ...chunk('PLTE', [1, 2, 3]),
          ...chunk('tRNS', [255]),
          ...chunk('IDAT', [9, 8, 7]),
          ...chunk('IEND', []),
        ]),
      );
      for (final secret in ['Exif', 'GPS', 'Juan', 'xmp', 'iCCP']) {
        expect(_text(stripped), isNot(contains(secret)), reason: secret);
      }
    });

    test('60 Mpx declared are rejected', () {
      final png = Uint8List.fromList([
        ...signature,
        ...chunk('IHDR', ihdr(10000, 6000)),
        ...chunk('IDAT', [9, 8, 7]),
        ...chunk('IEND', []),
      ]);

      expect(
        () => stripImageMetadata(png),
        throwsA(isA<UnsupportedImageException>()),
      );
    });

    test('a file without a header is rejected', () {
      final png = Uint8List.fromList([
        ...signature,
        ...chunk('tEXt', ascii.encode('Author\u0000Juan')),
        ...chunk('IDAT', [9, 8, 7]),
        ...chunk('IEND', []),
      ]);

      expect(
        () => stripImageMetadata(png),
        throwsA(isA<UnsupportedImageException>()),
      );
    });

    test('a damaged chunk length is rejected, not copied', () {
      final png = Uint8List.fromList([
        ...signature,
        ...chunk('IHDR', ihdr(2, 2)),
        0x7F,
        0xFF,
        0xFF,
        0xFF,
        ...ascii.encode('tEXtsecret'),
      ]);

      expect(
        () => stripImageMetadata(png),
        throwsA(isA<UnsupportedImageException>()),
      );
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
