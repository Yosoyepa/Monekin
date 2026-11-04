// Rebuilds a photo from a list of what is allowed, so that nothing but the image leaves the phone or is stored.
// JPEG: the file is written again with SOI, a minimal JFIF APP0 made here (no thumbnail), the DQT, DHT, SOF, DRI and
// SOS segments with their image data, and EOI. APP1 to APP15 (APP2 and APP14 too) and COM are dropped; when the
// original had an Adobe APP14, one of 12 bytes with only the colour transform is made here. PNG: only IHDR, PLTE,
// tRNS, gAMA, sRGB, pHYs, IDAT and IEND stay (iCCP, text, eXIf and unknown chunks go). Any other format (WebP, HEIC,
// GIF...) is decoded with dart:ui, reduced to 2048 px on its longest side and written as a PNG, or rejected.
// The size limits apply first, to every format. A file that cannot be parsed is rejected, never copied.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The photo is not a JPEG or PNG and could not be converted to one.
class UnsupportedImageException implements Exception {
  const UnsupportedImageException([
    this.message = 'Only JPEG and PNG photos are accepted',
  ]);

  final String message;

  @override
  String toString() => 'UnsupportedImageException: $message';
}

/// Longest photo accepted and most pixels it may declare or decode to.
const _maxImageBytes = 25 * 1024 * 1024;
const _maxImagePixels = 50 * 1000 * 1000;

/// Longest side of a photo converted from another format.
const _maxConvertedSide = 2048;

/// [bytes] rebuilt without metadata when they are a JPEG or a PNG.
/// Throws [UnsupportedImageException] for any other format (use [normalizeImage] to convert it), for a file over the
/// size limits or one that cannot be parsed.
Uint8List stripImageMetadata(Uint8List bytes) {
  _checkBytes(bytes);
  if (_isJpeg(bytes)) return _rebuildJpeg(bytes);
  if (_isPng(bytes)) return _rebuildPng(bytes);
  throw const UnsupportedImageException();
}

/// [bytes] as a JPEG or PNG without metadata: a JPEG or PNG is rebuilt, any other format is decoded, reduced to at
/// most 2048 px on its longest side and written as a PNG. Throws [UnsupportedImageException] when it is over the
/// limits (25 MiB, 50 Mpx), cannot be decoded or is not an image. The limits are checked before anything is processed.
Future<Uint8List> normalizeImage(Uint8List bytes) async {
  _checkBytes(bytes);
  if (_isJpeg(bytes)) return _rebuildJpeg(bytes);
  if (_isPng(bytes)) return _rebuildPng(bytes);

  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0 || width * height > _maxImagePixels) {
      throw const UnsupportedImageException();
    }
    final longest = math.max(width, height);
    final scale = longest > _maxConvertedSide ? _maxConvertedSide / longest : 1;
    codec = await descriptor.instantiateCodec(
      targetWidth: scale < 1 ? math.max(1, (width * scale).round()) : null,
      targetHeight: scale < 1 ? math.max(1, (height * scale).round()) : null,
    );
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const UnsupportedImageException();
    return _rebuildPng(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  } on UnsupportedImageException {
    rethrow;
  } catch (_) {
    throw const UnsupportedImageException();
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

void _checkBytes(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > _maxImageBytes) {
    throw const UnsupportedImageException();
  }
}

void _checkPixels(int width, int height) {
  if (width <= 0 || height <= 0 || width * height > _maxImagePixels) {
    throw const UnsupportedImageException();
  }
}

bool _isJpeg(Uint8List b) =>
    b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

bool _isPng(Uint8List b) {
  if (b.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (b[i] != _pngSignature[i]) return false;
  }
  return true;
}

/// SOF markers: C0 to CF but DHT (C4), JPG (C8) and DAC (CC).
bool _isSof(int marker) =>
    marker >= 0xC0 &&
    marker <= 0xCF &&
    marker != 0xC4 &&
    marker != 0xC8 &&
    marker != 0xCC;

/// Markers kept as they are, with their length and payload.
bool _isKeptJpegSegment(int marker) =>
    marker == 0xDB || marker == 0xC4 || marker == 0xDD || _isSof(marker);

/// A JFIF APP0 of version 1.01 with no density and no thumbnail.
final _jfif = Uint8List.fromList([
  0xFF, 0xE0, 0x00, 0x10, //
  0x4A, 0x46, 0x49, 0x46, 0x00, // JFIF\0
  0x01, 0x01, // version
  0x00, // no units
  0x00, 0x01, 0x00, 0x01, // density 1:1
  0x00, 0x00, // no thumbnail
]);

/// An Adobe APP14 of 12 bytes of payload: the signature, version 100, no flags and only the colour [transform].
Uint8List _adobe(int transform) => Uint8List.fromList([
  0xFF, 0xEE, 0x00, 0x0E, //
  ...ascii.encode('Adobe'),
  0x00, 0x64, // version
  0x00, 0x00, // flags 0
  0x00, 0x00, // flags 1
  transform,
]);

Uint8List _rebuildJpeg(Uint8List b) {
  final n = b.length;
  final kept = BytesBuilder(copy: false);
  int? adobeTransform;
  var sawSof = false;
  var sawScan = false;
  var i = 2;
  while (i + 1 < n) {
    if (b[i] != 0xFF) break;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xD9) break;
    // Markers with no length (TEM, RSTn, SOI) have no place between segments: they are dropped.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      i += 2;
      continue;
    }
    if (i + 3 >= n) break;
    final length = (b[i + 2] << 8) | b[i + 3];
    final start = i;
    final end = i + 2 + length;
    if (length < 2 || end > n) break;

    if (_isSof(marker)) {
      if (!sawSof && length >= 8) {
        _checkPixels((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
      }
      sawSof = true;
    }
    if (marker == 0xEE &&
        length >= 14 &&
        ascii.decode(b.sublist(i + 4, i + 9), allowInvalid: true) == 'Adobe') {
      adobeTransform = b[i + 15];
    }
    if (_isKeptJpegSegment(marker)) {
      kept.add(Uint8List.sublistView(b, start, end));
    }
    i = end;
    if (marker == 0xDA) {
      if (!sawSof) throw const UnsupportedImageException();
      sawScan = true;
      kept.add(Uint8List.sublistView(b, start, end));
      // Scan data runs to the next marker that is not a stuffed 0xFF00, a restart or a fill byte.
      var j = i;
      while (j + 1 < n) {
        if (b[j] == 0xFF) {
          final next = b[j + 1];
          if (next == 0xFF) {
            j++;
            continue;
          }
          if (next != 0x00 && !(next >= 0xD0 && next <= 0xD7)) break;
        }
        j++;
      }
      if (j + 1 >= n) j = n;
      kept.add(Uint8List.sublistView(b, i, j));
      i = j;
    }
  }
  if (!sawSof || !sawScan) throw const UnsupportedImageException();
  return (BytesBuilder(copy: false)
        ..add(const [0xFF, 0xD8])
        ..add(_jfif)
        ..add(adobeTransform == null ? Uint8List(0) : _adobe(adobeTransform))
        ..add(kept.takeBytes())
        ..add(const [0xFF, 0xD9]))
      .takeBytes();
}

const _allowedPngChunks = {
  'IHDR',
  'PLTE',
  'tRNS',
  'gAMA',
  'sRGB',
  'pHYs',
  'IDAT',
  'IEND',
};

Uint8List _rebuildPng(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(_pngSignature);
  final n = b.length;
  var i = _pngSignature.length;
  var first = true;
  var sawData = false;
  var sawEnd = false;
  while (i + 12 <= n) {
    final length = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final end = i + 12 + length;
    if (end > n) break;
    final type = ascii.decode(b.sublist(i + 4, i + 8), allowInvalid: true);
    if (first) {
      // The header comes first and says the size: check it before keeping anything else.
      if (type != 'IHDR' || length != 13) {
        throw const UnsupportedImageException();
      }
      final width =
          (b[i + 8] << 24) | (b[i + 9] << 16) | (b[i + 10] << 8) | b[i + 11];
      final height =
          (b[i + 12] << 24) | (b[i + 13] << 16) | (b[i + 14] << 8) | b[i + 15];
      _checkPixels(width, height);
      first = false;
    }
    if (_allowedPngChunks.contains(type)) {
      out.add(Uint8List.sublistView(b, i, end));
    }
    if (type == 'IDAT') sawData = true;
    i = end;
    if (type == 'IEND') {
      sawEnd = true;
      break;
    }
  }
  if (first || !sawData || !sawEnd) throw const UnsupportedImageException();
  return out.takeBytes();
}
