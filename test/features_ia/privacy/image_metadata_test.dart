// F-09: every photo is decoded and written again from its pixels, so no byte of the file reaches the disk or the provider.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/privacy/image_metadata.dart';

import 'jpeg_fixture.dart';

const _fixtures = [
  'exito_01.jpg',
  'e2e_01_supermercado.jpg',
  'e2e_02_drogueria.jpg',
  'e2e_03_restaurante.jpg',
  'blind3_farmacia.jpg',
  'blind3_panaderia.jpg',
];

Future<(int, int)> _decodedSize(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final image = (await codec.getNextFrame()).image;
    final size = (image.width, image.height);
    image.dispose();
    return size;
  } finally {
    codec.dispose();
  }
}

/// Whether any window of [window] bytes of [data] is somewhere in [out].
bool _containsWindowOf(Uint8List out, List<int> data, {int window = 32}) {
  final haystack = latin1.decode(out);
  for (var i = 0; i + window <= data.length; i++) {
    if (haystack.contains(latin1.decode(data.sublist(i, i + window)))) {
      return true;
    }
  }
  return false;
}

bool _isPng(Uint8List b) =>
    b.length > 8 && List.generate(8, (i) => b[i]).join() == pngSignature.join();

/// A file that only knows its length: it fails the test if anybody reads it.
class _LengthOnlyFile implements File {
  _LengthOnlyFile(this._length);

  final int _length;
  var reads = 0;

  @override
  Future<int> length() async => _length;

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return Uint8List(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [width] x [height] PNG of random pixels, which compresses badly.
Uint8List _noisePng(int width, int height) {
  final random = math.Random(7);
  final raw = BytesBuilder();
  final row = Uint8List(1 + width * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 1; x < row.length; x++) {
      row[x] = random.nextInt(256);
    }
    raw.add(row);
  }
  return Uint8List.fromList([
    ...pngSignature,
    ...pngChunk('IHDR', [
      width >> 24 & 0xFF,
      width >> 16 & 0xFF,
      width >> 8 & 0xFF,
      width & 0xFF,
      height >> 24 & 0xFF,
      height >> 16 & 0xFF,
      height >> 8 & 0xFF,
      height & 0xFF,
      8, 2, 0, 0, 0, //
    ]),
    ...pngChunk('IDAT', ZLibCodec(level: 0).encode(raw.takeBytes())),
    ...pngChunk('IEND', const []),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PNG', () {
    test(
      'data inside IDAT after the zlib stream and pHYs do not survive',
      () async {
        final original = pngWithDataInIdat();
        expect(latin1.decode(original), contains(pngHiddenMarker));
        expect(latin1.decode(original), contains('pHYs'));

        final out = await normalizeImage(original);

        expect(_isPng(out), isTrue);
        expect(latin1.decode(out), isNot(contains('GPS-PRIVATE')));
        expect(latin1.decode(out), isNot(contains('pHYs')));
        expect(_containsWindowOf(out, ascii.encode(pngHiddenMarker)), isFalse);
        expect(await _decodedSize(out), (1, 1));
      },
    );

    test('a plain PNG is written again, not copied', () async {
      final original = minimalPng();

      final out = await normalizeImage(original);

      expect(_isPng(out), isTrue);
      expect(await _decodedSize(out), (1, 1));
    });

    test('a PNG with a damaged header or no data is rejected', () async {
      final cut = Uint8List.sublistView(minimalPng(), 0, 40);
      final noHeader = Uint8List.fromList([
        ...pngSignature,
        ...pngChunk('tEXt', ascii.encode('Author\u0000Juan')),
        ...pngChunk('IEND', const []),
      ]);
      for (final bytes in [cut, noHeader]) {
        await expectLater(
          normalizeImage(bytes),
          throwsA(isA<UnsupportedImageException>()),
        );
      }
    });
  });

  group('JPEG', () {
    test('no marker survives, nor the bytes after the end of image', () async {
      final original = jpegWithMetadata();
      for (final entry in jpegHiddenData.entries) {
        expect(
          latin1.decode(original),
          contains(latin1.decode(entry.value)),
          reason: '${entry.key} is in the fixture',
        );
      }

      final out = await normalizeImage(original);

      expect(_isPng(out), isTrue);
      expect(await _decodedSize(out), (2, 2));
      final text = latin1.decode(out);
      for (final secret in [
        'PRIVATE',
        'GPS',
        'Exif',
        'xmpmeta',
        'ICC',
        'Adobe',
        'JFIF',
        'THUMBNAIL',
        'camera',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      for (final entry in jpegHiddenData.entries) {
        expect(_containsWindowOf(out, entry.value), isFalse, reason: entry.key);
      }
    });

    test('a file cut before the image data is rejected, not copied', () async {
      final cut = Uint8List.sublistView(jpegWithMetadata(), 0, 40);

      await expectLater(
        normalizeImage(cut),
        throwsA(isA<UnsupportedImageException>()),
      );
    });
  });

  group('limits', () {
    test('over 25 MiB is rejected for every format', () async {
      final huge = Uint8List(25 * 1024 * 1024 + 1);
      for (final prefix in [
        ascii.encode('RIFF'),
        [0xFF, 0xD8, 0xFF],
        pngSignature,
      ]) {
        huge.setRange(0, prefix.length, prefix);
        await expectLater(
          normalizeImage(huge),
          throwsA(isA<UnsupportedImageException>()),
        );
      }
    });

    test('a file over 25 MiB is rejected without reading it', () async {
      final file = _LengthOnlyFile(25 * 1024 * 1024 + 1);

      await expectLater(
        normalizeImageFile(file),
        throwsA(isA<UnsupportedImageException>()),
      );
      expect(file.reads, 0);
    });

    test('an empty file is rejected without reading it', () async {
      final file = _LengthOnlyFile(0);

      await expectLater(
        normalizeImageFile(file),
        throwsA(isA<UnsupportedImageException>()),
      );
      expect(file.reads, 0);
    });

    test('a real file over 25 MiB is rejected', () async {
      final dir = Directory.systemTemp.createTempSync('image_limit_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/huge.png');
      final handle = file.openSync(mode: FileMode.write);
      handle
        ..setPositionSync(25 * 1024 * 1024)
        ..writeByteSync(0)
        ..closeSync();

      await expectLater(
        normalizeImageFile(file),
        throwsA(isA<UnsupportedImageException>()),
      );
    });

    test('a missing file is rejected', () async {
      await expectLater(
        normalizeImageFile(File('${Directory.systemTemp.path}/no_such_photo')),
        throwsA(isA<UnsupportedImageException>()),
      );
    });

    test('60 Mpx declared are rejected before they are decoded', () async {
      final png = Uint8List.fromList([
        ...pngSignature,
        ...pngChunk('IHDR', [
          0,
          0,
          0x27,
          0x10,
          0,
          0,
          0x17,
          0x70,
          8,
          2,
          0,
          0,
          0,
        ]),
        ...pngChunk('IDAT', zlib.encode([0, 255, 0, 0])),
        ...pngChunk('IEND', const []),
      ]);
      final jpeg = Uint8List.fromList([
        0xFF,
        0xD8,
        ...jpegSegment(0xC0, [8, 0x17, 0x70, 0x27, 0x10, 1, 1, 0x11, 0]),
        ...jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]),
        1,
        0xFF,
        0xD9,
      ]);

      for (final bytes in [png, jpeg]) {
        await expectLater(
          normalizeImage(bytes),
          throwsA(isA<UnsupportedImageException>()),
        );
      }
    });

    test('bytes that no decoder reads are rejected', () async {
      for (final bytes in [
        Uint8List.fromList(ascii.encode('not an image at all')),
        Uint8List.fromList(
          ascii.encode('RIFF\u0000\u0000\u0000\u0000WEBPEXIF GPS-SECRET'),
        ),
        Uint8List(0),
      ]) {
        await expectLater(
          normalizeImage(bytes),
          throwsA(isA<UnsupportedImageException>()),
        );
      }
    });

    test(
      'a photo that weighs over 7 MB as a PNG is reduced in steps',
      () async {
        final noise = _noisePng(2400, 1800);
        expect(noise.length, lessThan(25 * 1024 * 1024));

        final out = await normalizeImage(noise);

        expect(_isPng(out), isTrue);
        expect(out.length, lessThanOrEqualTo(7 * 1000 * 1000));
        final (width, height) = await _decodedSize(out);
        expect(math.max(width, height), lessThan(2048));
        expect(math.max(width, height), greaterThanOrEqualTo(1280));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('receipt fixtures', () {
    for (final name in _fixtures) {
      test(
        '$name is rebuilt as a PNG under 7 MB with none of its bytes',
        () async {
          final original = File(
            'test/features_ia/fixtures/receipts/$name',
          ).readAsBytesSync();

          final out = await normalizeImage(original);

          // ignore: avoid_print
          print(
            'FIXTURE $name: ${original.length} B jpg -> ${out.length} B png',
          );
          expect(_isPng(out), isTrue);
          expect(out.length, lessThan(7 * 1000 * 1000));
          final (width, height) = await _decodedSize(out);
          expect(math.max(width, height), lessThanOrEqualTo(2048));
          // 32 bytes from 200 places of the original, spread over the whole file.
          final haystack = latin1.decode(out);
          final step = (original.length - 32) ~/ 200;
          for (var at = 0; at + 32 <= original.length; at += step) {
            expect(
              haystack.contains(latin1.decode(original.sublist(at, at + 32))),
              isFalse,
              reason: 'bytes $at to ${at + 32}',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );
    }
  });
}
