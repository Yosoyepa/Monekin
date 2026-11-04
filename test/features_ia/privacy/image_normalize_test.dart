// F-09: formats other than JPEG and PNG are decoded and written as a PNG of at most 2048 px too, or rejected.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/privacy/image_metadata.dart';

const _png8 = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// A 1x1 GIF with a comment extension that carries a secret.
Uint8List _gifWithComment() => Uint8List.fromList([
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
  0x00, //
  0x21, 0xFE, 12, ...ascii.encode('GPS-SECRET-1'), 0x00,
  0x21, 0xF9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00,
  0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
  0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
]);

/// A WebP made of a VP8X header, a lossless 1x1 image and an EXIF chunk with a secret.
Uint8List _webpWithExif() {
  final lossless = base64Decode(
    'UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==',
  );
  final vp8l = lossless.sublist(12); // 'VP8L' + size + payload (+ pad)
  final exif = [...ascii.encode('Exif\u0000\u0000GPS-SECRET-2')];
  final exifChunk = [
    ...ascii.encode('EXIF'),
    exif.length,
    0,
    0,
    0,
    ...exif,
    if (exif.length.isOdd) 0,
  ];
  final vp8x = [
    ...ascii.encode('VP8X'),
    10, 0, 0, 0,
    0x08 | 0x20, 0, 0, 0, // flags: EXIF + (ICC bit unused)
    0, 0, 0, // width - 1
    0, 0, 0, // height - 1
  ];
  final body = [...ascii.encode('WEBP'), ...vp8x, ...vp8l, ...exifChunk];
  return Uint8List.fromList([
    ...ascii.encode('RIFF'),
    body.length & 0xFF,
    (body.length >> 8) & 0xFF,
    (body.length >> 16) & 0xFF,
    (body.length >> 24) & 0xFF,
    ...body,
  ]);
}

/// A lossless WebP of one colour that declares [width] x [height]: its codes take no bits per pixel.
Uint8List _webpOfSize(int width, int height) {
  final lossless = base64Decode(
    'UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==',
  );
  final vp8l = Uint8List.fromList(lossless.sublist(12));
  final header = (width - 1) | ((height - 1) << 14) | (1 << 28);
  vp8l.setRange(9, 13, [
    header & 0xFF,
    header >> 8 & 0xFF,
    header >> 16 & 0xFF,
    header >> 24 & 0xFF,
  ]);
  final body = [...ascii.encode('WEBP'), ...vp8l];
  return Uint8List.fromList([
    ...ascii.encode('RIFF'),
    body.length & 0xFF,
    (body.length >> 8) & 0xFF,
    (body.length >> 16) & 0xFF,
    (body.length >> 24) & 0xFF,
    ...body,
  ]);
}

/// Width and height of a PNG, from its header.
(int, int) _pngSize(Uint8List png) {
  final data = ByteData.sublistView(png);
  return (data.getUint32(16), data.getUint32(20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a GIF with a comment leaves as a PNG without it', () async {
    final out = await normalizeImage(_gifWithComment());

    expect(out.sublist(0, 8), _png8);
    expect(latin1.decode(out), isNot(contains('SECRET')));
    expect(latin1.decode(out), isNot(contains('GIF')));
  });

  test(
    'a WebP with EXIF does not leave as it is: PNG without the EXIF',
    () async {
      final webp = _webpWithExif();
      expect(latin1.decode(webp), contains('GPS-SECRET-2'));

      final out = await normalizeImage(webp);

      expect(out.sublist(0, 8), _png8);
      expect(out, isNot(equals(webp)));
      expect(latin1.decode(out), isNot(contains('GPS-SECRET')));
      expect(latin1.decode(out), isNot(contains('Exif')));
      expect(latin1.decode(out), isNot(contains('WEBP')));
    },
  );

  test('bytes that no decoder reads are rejected', () async {
    for (final bytes in [
      Uint8List.fromList(
        ascii.encode('RIFF\u0000\u0000\u0000\u0000WEBPEXIF GPS-SECRET'),
      ),
      Uint8List.fromList(ascii.encode('not an image at all')),
      Uint8List(0),
    ]) {
      await expectLater(
        normalizeImage(bytes),
        throwsA(isA<UnsupportedImageException>()),
      );
    }
  });

  test(
    'a WebP larger than 2048 px leaves as a PNG of at most 2048 px',
    () async {
      final out = await normalizeImage(_webpOfSize(3000, 1000));

      expect(out.sublist(0, 8), _png8);
      final (width, height) = _pngSize(out);
      expect(width, 2048);
      expect(height, closeTo(683, 1));
    },
  );

  test('a small WebP keeps its size', () async {
    final out = await normalizeImage(_webpOfSize(40, 30));

    expect(_pngSize(out), (40, 30));
  });

  test('a WebP of 60 Mpx is rejected before it is decoded', () async {
    await expectLater(
      normalizeImage(_webpOfSize(10000, 6000)),
      throwsA(isA<UnsupportedImageException>()),
    );
  });

  test('over 25 MiB is rejected for every format', () async {
    final huge = Uint8List(25 * 1024 * 1024 + 1);
    for (final prefix in [
      ascii.encode('RIFF'),
      [0xFF, 0xD8, 0xFF],
      _png8,
    ]) {
      huge.setRange(0, prefix.length, prefix);
      await expectLater(
        normalizeImage(huge),
        throwsA(isA<UnsupportedImageException>()),
      );
    }
  });
}
