// Receipt photo storage (T002). Owner: w-recibos.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class SavedReceiptPhoto {
  const SavedReceiptPhoto({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;

  String get fileName => p.basename(path);
}

/// Copies [source] to `<documents>/finanzas_ia/receipts/<uuid>.jpg`.
Future<SavedReceiptPhoto> saveReceiptPhoto(
  File source, {
  Directory? baseDir,
}) async {
  final docs = baseDir ?? await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'finanzas_ia', 'receipts'));
  await dir.create(recursive: true);
  final target = File(p.join(dir.path, '${const Uuid().v4()}.jpg'));
  final bytes = await source.readAsBytes();
  await target.writeAsBytes(bytes, flush: true);
  return SavedReceiptPhoto(path: target.path, bytes: bytes);
}
