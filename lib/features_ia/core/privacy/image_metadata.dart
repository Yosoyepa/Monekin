// Rebuilds every photo from its pixels, so that nothing but the image leaves the phone or is stored.
// The file is decoded with dart:ui, reduced to at most 2048 px on its longest side and written again as a PNG. No byte
// of the original is copied: segments, chunks, thumbnails and trailing bytes (inside IDAT or after EOI too) are gone
// because only the decoded pixels are written. A PNG too big for the provider (7 MB) is made smaller in steps
// (2048, 1600, 1280 px). A file that cannot be decoded is rejected, never copied.
// The size limits apply first: the length of a file is checked before it is read, and the pixels it declares before
// it is decoded.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The photo is not an image that could be decoded or is over the limits.
class UnsupportedImageException implements Exception {
  const UnsupportedImageException([this.message = 'The photo cannot be used']);

  final String message;

  @override
  String toString() => 'UnsupportedImageException: $message';
}

/// Longest photo accepted and most pixels it may declare.
const _maxImageBytes = 25 * 1024 * 1024;
const _maxImagePixels = 50 * 1000 * 1000;

/// Most a rebuilt PNG may weigh, which is what the provider takes.
const _maxResultBytes = 7 * 1000 * 1000;

/// Longest side of the rebuilt photo, from the first try to the last.
const _sides = [2048, 1600, 1280];

/// The photo at [file] rebuilt from its pixels (see [normalizeImage]). Its length is checked before any byte is read.
Future<Uint8List> normalizeImageFile(File file) async {
  final int length;
  try {
    length = await file.length();
  } on FileSystemException {
    throw const UnsupportedImageException();
  }
  if (length <= 0 || length > _maxImageBytes) {
    throw const UnsupportedImageException();
  }
  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } on FileSystemException {
    throw const UnsupportedImageException();
  }
  return normalizeImage(bytes);
}

/// [bytes] decoded and written again as a PNG of at most 2048 px on its longest side and [_maxResultBytes]. Throws
/// [UnsupportedImageException] when it is over the limits (25 MiB, 50 Mpx), cannot be decoded or is not an image.
/// The limits are checked before anything is decoded.
Future<Uint8List> normalizeImage(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > _maxImageBytes) {
    throw const UnsupportedImageException();
  }

  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0 || width * height > _maxImagePixels) {
      throw const UnsupportedImageException();
    }
    final longest = math.max(width, height);
    var lastWidth = 0;
    for (final side in _sides) {
      final scale = longest > side ? side / longest : 1.0;
      final targetWidth = math.max(1, (width * scale).round());
      final targetHeight = math.max(1, (height * scale).round());
      // A smaller step that gives the same size as the one before it cannot help.
      if (targetWidth == lastWidth) break;
      lastWidth = targetWidth;
      final png = await _encodePng(descriptor, targetWidth, targetHeight);
      if (png.length <= _maxResultBytes) return png;
    }
    throw const UnsupportedImageException();
  } on UnsupportedImageException {
    rethrow;
  } catch (_) {
    throw const UnsupportedImageException();
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<Uint8List> _encodePng(
  ui.ImageDescriptor descriptor,
  int width,
  int height,
) async {
  final resize = width != descriptor.width || height != descriptor.height;
  final codec = await descriptor.instantiateCodec(
    targetWidth: resize ? width : null,
    targetHeight: resize ? height : null,
  );
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const UnsupportedImageException();
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    image?.dispose();
    codec.dispose();
  }
}
