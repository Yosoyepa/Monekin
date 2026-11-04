// Removes the metadata of a photo (location, device, authorship) before it is stored or sent to the AI provider.
// Segment filters with no dependencies: JPEG loses APP1 (Exif/XMP), APP13 (IPTC) and COM; PNG loses tEXt, iTXt, zTXt and eXIf.
// Bytes that cannot be parsed are never copied: a damaged file ends where the damage starts.
import 'dart:convert';
import 'dart:typed_data';

/// [bytes] without metadata when they are a JPEG or a PNG; any other format is returned as it is.
Uint8List stripImageMetadata(Uint8List bytes) {
  if (_isJpeg(bytes)) return _stripJpeg(bytes);
  if (_isPng(bytes)) return _stripPng(bytes);
  return bytes;
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
    final isMetadata = marker == 0xE1 || marker == 0xED || marker == 0xFE;
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
