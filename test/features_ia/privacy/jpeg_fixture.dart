// A small JPEG with Exif/GPS, XMP, IPTC, a comment and a trailer, to check that no metadata is stored or sent.
import 'dart:convert';
import 'dart:typed_data';

import 'package:monekin/features_ia/core/privacy/image_metadata.dart';

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

final exifPayload = [
  ...ascii.encode('Exif'),
  0,
  0,
  ...ascii.encode('MM GPSLatitude 4.7110 GPSLongitude -74.0721 Make Acme'),
];

/// Scan data with a stuffed FF00 followed by 0xE1, a restart marker and plain bytes.
const jpegScanData = [
  0x12, 0xFF, 0x00, 0xE1, 0x34, 0xFF, 0xD0, 0x56, 0xFF, 0x00, 0xFE, //
];

Uint8List jpegWithMetadata() => Uint8List.fromList([
  0xFF, 0xD8,
  ...jpegSegment(0xE0, ascii.encode('JFIF\u0000\u0001\u0001')),
  ...jpegSegment(0xE1, exifPayload),
  ...jpegSegment(
    0xE1,
    ascii.encode('http://ns.adobe.com/xap/1.0/\u0000<x:xmpmeta/>'),
  ),
  ...jpegSegment(0xED, ascii.encode('Photoshop 3.0\u0000IPTC owner')),
  ...jpegSegment(0xFE, ascii.encode('written by a camera')),
  ...jpegSegment(0xDB, List.filled(65, 7)),
  ...jpegSegment(0xC0, [8, 0, 2, 0, 2, 1, 1, 0x11, 0]),
  ...jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]),
  ...jpegScanData,
  0xFF, 0xD9,
  // Trailer after the end of image, such as a maker note or an embedded picture.
  ...ascii.encode('Exif trailer with GPS'),
]);

/// The smallest JPEG the importers accept (2 x 2), already in the form they write: nothing is added or removed
/// when it is stored or sent.
Uint8List minimalJpeg() => stripImageMetadata(
  Uint8List.fromList([
    0xFF, 0xD8,
    ...jpegSegment(0xDB, List.filled(65, 7)),
    ...jpegSegment(0xC0, [8, 0, 2, 0, 2, 1, 1, 0x11, 0]),
    ...jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]),
    1, 2, 3,
    0xFF, 0xD9, //
  ]),
);

/// The smallest PNG the importers accept (1 x 1): header, one data chunk and the end.
Uint8List minimalPng() => Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 13, ...ascii.encode('IHDR'),
  0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 1, ...ascii.encode('IDAT'), 7, 0, 0, 0, 0,
  0, 0, 0, 0, ...ascii.encode('IEND'), 0, 0, 0, 0,
]);
