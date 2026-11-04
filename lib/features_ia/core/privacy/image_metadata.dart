// Removes the metadata of a photo (location, device, authorship) before it is stored or sent to the AI provider.
// Only JPEG and PNG are accepted. Segment filters with no dependencies: JPEG keeps APP0 (JFIF), APP2 (ICC profile) and
// APP14 (Adobe) and loses every other APPn and COM; PNG loses tEXt, iTXt, zTXt and eXIf. Any other format (WebP, HEIC,
// GIF...) is decoded with dart:ui and written again as a PNG, which carries no metadata, or rejected.
// Bytes that cannot be parsed are never copied: a damaged file ends where the damage starts.
import 'dart:convert';
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

/// Longest photo accepted and most pixels it may decode to.
const _maxImageBytes = 25 * 1024 * 1024;
const _maxImagePixels = 50 * 1000 * 1000;

/// [bytes] without metadata when they are a JPEG or a PNG.
/// Throws [UnsupportedImageException] for any other format: use [normalizeImage] to convert it.
Uint8List stripImageMetadata(Uint8List bytes) {
  if (_isJpeg(bytes)) return _stripJpeg(bytes);
  if (_isPng(bytes)) return _stripPng(bytes);
  throw const UnsupportedImageException();
}

/// [bytes] as a JPEG or PNG without metadata: a JPEG or PNG is stripped, any other format is decoded and written as
/// a PNG. Throws [UnsupportedImageException] when it is too large, cannot be decoded or is not an image.
Future<Uint8List> normalizeImage(Uint8List bytes) async {
  if (_isJpeg(bytes) || _isPng(bytes)) return stripImageMetadata(bytes);
  if (bytes.isEmpty || bytes.length > _maxImageBytes) {
    throw const UnsupportedImageException();
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > _maxImagePixels) {
      throw const UnsupportedImageException();
    }
    codec = await descriptor.instantiateCodec();
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const UnsupportedImageException();
    return stripImageMetadata(
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

Uint8List _stripJpeg(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  final n = b.length;
  var i = 2;
  while (i + 1 < n) {
    if (b[i] != 0xFF) break;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xD9) {
      // End of image: whatever follows (maker trailers, extra images) is dropped.
      out.add(const [0xFF, 0xD9]);
      break;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      out.add(Uint8List.sublistView(b, i, i + 2));
      i += 2;
      continue;
    }
    if (i + 3 >= n) break;
    final length = (b[i + 2] << 8) | b[i + 3];
    final end = i + 2 + length;
    if (length < 2 || end > n) break;
    final isMetadata = _isDroppedJpegSegment(marker);
    if (!isMetadata) out.add(Uint8List.sublistView(b, i, end));
    i = end;
    if (marker == 0xDA) {
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
      out.add(Uint8List.sublistView(b, i, j));
      i = j;
    }
  }
  return out.takeBytes();
}

/// COM and every APPn but APP0 (JFIF), APP2 (ICC profile) and APP14 (Adobe).
bool _isDroppedJpegSegment(int marker) =>
    marker == 0xFE ||
    (marker >= 0xE1 && marker <= 0xEF && marker != 0xE2 && marker != 0xEE);

const _droppedPngChunks = {'tEXt', 'iTXt', 'zTXt', 'eXIf'};

Uint8List _stripPng(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(_pngSignature);
  final n = b.length;
  var i = _pngSignature.length;
  while (i + 12 <= n) {
    final length = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final end = i + 12 + length;
    if (length < 0 || end > n) break;
    final type = ascii.decode(b.sublist(i + 4, i + 8), allowInvalid: true);
    if (!_droppedPngChunks.contains(type)) {
      out.add(Uint8List.sublistView(b, i, end));
    }
    i = end;
    if (type == 'IEND') break;
  }
  return out.takeBytes();
}
