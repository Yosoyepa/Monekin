// Receipt photo storage (T002). Owner: w-recibos.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:monekin/features_ia/core/privacy/image_metadata.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class SavedReceiptPhoto {
  const SavedReceiptPhoto({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;

  String get fileName => p.basename(path);
}

/// `<documents>/finanzas_ia/receipts`, where the photos live.
Future<Directory> receiptsDirectory({Directory? baseDir}) async {
  final docs = baseDir ?? await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'finanzas_ia', 'receipts'));
}

/// Writes [source] to `<documents>/finanzas_ia/receipts/<uuid>.png`, rebuilt from its pixels: nothing of the original
/// file (Exif, GPS, trailing bytes) is copied. Throws [UnsupportedImageException] when the photo cannot be used.
Future<SavedReceiptPhoto> saveReceiptPhoto(
  File source, {
  Directory? baseDir,
}) async {
  final bytes = await normalizeImageFile(source);
  final dir = await receiptsDirectory(baseDir: baseDir);
  await dir.create(recursive: true);
  final target = File(p.join(dir.path, '${const Uuid().v4()}.png'));
  await target.writeAsBytes(bytes, flush: true);
  return SavedReceiptPhoto(path: target.path, bytes: bytes);
}

/// Deletes the photo of a receipt that will not be saved. A failed delete only leaves a stray file.
void deleteReceiptPhoto(SavedReceiptPhoto photo) {
  try {
    File(photo.path).deleteSync();
  } on FileSystemException {
    // Nothing refers to the file any more.
  }
}

final _receiptFileName = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png)$',
);

/// Whether [name] has the shape `saveReceiptPhoto` gives its files (`<uuid v4>.jpg` or `.png`).
bool isReceiptFileName(String name) => _receiptFileName.hasMatch(name);

/// Name of the file at [path], whichever separator it was stored with.
String storedFileName(String path) => path.split(RegExp(r'[\\/]')).last;

/// Whether [path] is a plain file, not a link, named like a saved receipt and directly
/// inside [receiptsDir] once both are resolved. Only such a file is ours to delete.
Future<bool> isOwnedReceiptFile(String path, Directory receiptsDir) async {
  try {
    if (!isReceiptFileName(p.basename(path))) return false;
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final dir = await receiptsDir.resolveSymbolicLinks();
    final resolved = await File(path).resolveSymbolicLinks();
    return p.equals(p.dirname(resolved), dir);
  } on FileSystemException {
    return false;
  }
}
