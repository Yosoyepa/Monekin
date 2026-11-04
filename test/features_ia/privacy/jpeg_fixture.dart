// Small photos that carry metadata in every place a file can hide it, to check that no byte of the original is stored or sent.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Uint8List jpegSegment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    marker,
    length >> 8,
    length & 0xFF,
    ...payload,
  ]);
}

/// A 2 x 2 JPEG that a decoder reads (JFIF header, two quantization tables, Huffman tables, one scan).
final _plainJpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxl'
  'Z2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAACAAIDASIAAhEB'
  'AxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS'
  '0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKz'
  'tLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgEC'
  'BAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpj'
  'ZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6'
  '/9oADAMBAAIRAxEAPwDHooorhPqD/9k=',
);

/// A JPEG the importers accept (2 x 2), as a camera or a gallery gives it.
Uint8List minimalJpeg() => Uint8List.fromList(_plainJpeg);

/// What the adversarial JPEG hides, one string per place. Each one is at least 32 bytes, so that a window of 32 bytes
/// of it can be looked for in the output.
final jpegHiddenData = <String, List<int>>{
  'APP0 thumbnail': [
    ...ascii.encode('JFIF\u0000\u0001\u0002\u0000\u0000\u0001\u0000\u0001'),
    ...ascii.encode('THUMBNAIL-PRIVATE-EXAMPLE-0123456789'),
  ],
  'APP1 Exif': [
    ...ascii.encode('Exif'),
    0,
    0,
    ...ascii.encode('MM GPSLatitude 4.7110 GPSLongitude -74.0721 Make Acme'),
  ],
  'APP1 XMP': ascii.encode(
    'http://ns.adobe.com/xap/1.0/\u0000<x:xmpmeta owner="XMP-PRIVATE-EXAMPLE-0123"/>',
  ),
  'APP2 ICC': ascii.encode(
    'ICC_PROFILE\u0000\u0001\u0001ICC-PRIVATE-EXAMPLE-0123456789',
  ),
  'APP14': ascii.encode('Adobe\u0000dAPP14-PRIVATE-EXAMPLE-0123456789ABCD'),
  'COM': ascii.encode('COM-PRIVATE-EXAMPLE written by a camera 0123456789'),
  'after EOI': ascii.encode(
    'Exif trailer with GPS-PRIVATE-EXAMPLE after the end',
  ),
};

/// A decodable JPEG with metadata in APP0 (inside the JFIF thumbnail), APP1 (Exif and XMP), APP2, APP14 and COM, and
/// bytes after the end of image.
Uint8List jpegWithMetadata() => Uint8List.fromList([
  ..._plainJpeg.sublist(0, 2),
  ...jpegSegment(0xE0, jpegHiddenData['APP0 thumbnail']!),
  ...jpegSegment(0xE1, jpegHiddenData['APP1 Exif']!),
  ...jpegSegment(0xE1, jpegHiddenData['APP1 XMP']!),
  ...jpegSegment(0xE2, jpegHiddenData['APP2 ICC']!),
  ...jpegSegment(0xEE, jpegHiddenData['APP14']!),
  ...jpegSegment(0xFE, jpegHiddenData['COM']!),
  ..._plainJpeg.sublist(2),
  ...jpegHiddenData['after EOI']!,
]);

/// A PNG chunk with its CRC.
Uint8List pngChunk(String type, List<int> data) {
  final body = [...ascii.encode(type), ...data];
  final crc = _crc32(body);
  return Uint8List.fromList([
    data.length >> 24 & 0xFF,
    data.length >> 16 & 0xFF,
    data.length >> 8 & 0xFF,
    data.length & 0xFF,
    ...body,
    crc >> 24 & 0xFF,
    crc >> 16 & 0xFF,
    crc >> 8 & 0xFF,
    crc & 0xFF,
  ]);
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// The smallest PNG the importers accept (1 x 1, one red pixel): header, one data chunk and the end.
Uint8List minimalPng() => Uint8List.fromList([
  ...pngSignature,
  ...pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]),
  ...pngChunk('IDAT', zlib.encode([0, 255, 0, 0])),
  ...pngChunk('IEND', const []),
]);

/// What the adversarial PNG hides inside IDAT, after the compressed stream.
const pngHiddenMarker = 'GPS-PRIVATE-EXAMPLE-IDAT-0123456789ABCDEF';

/// A valid 1 x 1 PNG (every CRC is right) with a pHYs chunk and a marker inside IDAT after the end of the zlib stream.
Uint8List pngWithDataInIdat() => Uint8List.fromList([
  ...pngSignature,
  ...pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]),
  ...pngChunk('pHYs', [0, 0, 0x0B, 0x13, 0, 0, 0x0B, 0x13, 1]),
  ...pngChunk('IDAT', [
    ...zlib.encode([0, 255, 0, 0]),
    ...ascii.encode(pngHiddenMarker),
  ]),
  ...pngChunk('IEND', const []),
]);
