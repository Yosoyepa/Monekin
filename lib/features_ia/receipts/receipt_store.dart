// Receipt photo storage and the photo -> inbox item step (T002). Owner: w-recibos.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';
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

/// Reads [photo] and stores the result in the inbox; the receipt is kept even if the AI fails.
Future<String> addReceiptToInbox(
  SavedReceiptPhoto photo, {
  required ReceiptAnalyzer analyzer,
  InboxService? inbox,
}) async {
  final InboxDraft draft = await analyzer.analyze(
    imageBytes: photo.bytes,
    filePath: photo.path,
    fileName: photo.fileName,
  );
  return (inbox ?? InboxService.instance).addItem(draft);
}
