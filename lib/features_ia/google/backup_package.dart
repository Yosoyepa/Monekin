// Versioned Drive backup package (T002): a zip with the database and the receipt photos.
// v1 copies are the bare SQLite file; they still restore.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

const kBackupFormat = 'finanzas-ia-backup';
const kBackupVersion = 2;

const _manifestName = 'manifest.json';
const _databaseName = 'database.db';
const _photosFolder = 'receipts/';

/// Limits on a Drive copy's zip. They are checked on the declared sizes, before any
/// entry is extracted.
const kMaxZipEntries = 5000;
const kMaxZipEntryBytes = 256 * 1024 * 1024;
const kMaxZipTotalBytes = 512 * 1024 * 1024;

/// `<documents>/finanzas_ia/receipts`, where `saveReceiptPhoto` keeps the photos.
String receiptsDirOf(String documentsDir) =>
    p.join(documentsDir, 'finanzas_ia', 'receipts');

enum InvalidBackupReason { corrupt, newerSchema }

/// The copy cannot be restored; the current database was not touched.
class InvalidBackupException implements Exception {
  const InvalidBackupException(this.reason, [this.detail]);

  final InvalidBackupReason reason;
  final String? detail;

  @override
  String toString() =>
      'InvalidBackupException: ${reason.name}${detail == null ? '' : ' ($detail)'}';
}

class BackupPackage {
  const BackupPackage({
    required this.database,
    this.photos = const {},
    this.schemaVersion,
    this.sourceDocumentsDir,
  });

  final Uint8List database;

  /// File name -> bytes of the receipt photos.
  final Map<String, Uint8List> photos;

  /// Null in v1 copies, which carry no manifest.
  final int? schemaVersion;
  final String? sourceDocumentsDir;
}

bool _isZip(Uint8List bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4b &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// Packs [database] and the photos found in `<documentsDir>/finanzas_ia/receipts`.
Future<Uint8List> buildBackupPackage({
  required Uint8List database,
  required String documentsDir,
  required int schemaVersion,
  required DateTime date,
}) async {
  final archive = Archive();
  final photosDir = Directory(receiptsDirOf(documentsDir));
  final photoNames = <String>[];

  if (await photosDir.exists()) {
    await for (final entity in photosDir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      photoNames.add(name);
      archive.add(
        ArchiveFile.bytes('$_photosFolder$name', await entity.readAsBytes()),
      );
    }
  }

  final manifest = {
    'format': kBackupFormat,
    'version': kBackupVersion,
    'createdAt': date.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
    'documentsDir': documentsDir,
    'photos': photoNames,
  };
  archive.add(ArchiveFile.string(_manifestName, jsonEncode(manifest)));
  archive.add(ArchiveFile.bytes(_databaseName, database));

  return ZipEncoder().encodeBytes(archive);
}

/// Rejects a zip with too many entries or too many declared bytes. Only the central
/// directory is read, so nothing is decompressed.
void _checkZipLimits(Archive archive) {
  if (archive.files.length > kMaxZipEntries) {
    throw InvalidBackupException(
      InvalidBackupReason.corrupt,
      'more than $kMaxZipEntries entries',
    );
  }

  var total = 0;
  for (final file in archive.files) {
    if (file.size > kMaxZipEntryBytes) {
      throw InvalidBackupException(
        InvalidBackupReason.corrupt,
        '${file.name} declares ${file.size} bytes',
      );
    }
    total += file.size;
    if (total > kMaxZipTotalBytes) {
      throw InvalidBackupException(
        InvalidBackupReason.corrupt,
        'uncompressed total over $kMaxZipTotalBytes bytes',
      );
    }
  }
}

/// Reads a Drive copy, whatever its version.
BackupPackage parseBackupPackage(Uint8List bytes) {
  if (!_isZip(bytes)) return BackupPackage(database: bytes);

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw InvalidBackupException(InvalidBackupReason.corrupt, '$e');
  }
  _checkZipLimits(archive);

  Uint8List? read(String name) => archive.findFile(name)?.readBytes();

  final manifestBytes = read(_manifestName);
  final database = read(_databaseName);
  if (manifestBytes == null || database == null) {
    throw const InvalidBackupException(
      InvalidBackupReason.corrupt,
      'the package has no manifest or database',
    );
  }

  final Map<String, dynamic> manifest;
  try {
    manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
  } catch (e) {
    throw InvalidBackupException(InvalidBackupReason.corrupt, 'manifest: $e');
  }
  if (manifest['format'] != kBackupFormat ||
      manifest['version'] is! int ||
      (manifest['version'] as int) > kBackupVersion) {
    throw InvalidBackupException(
      InvalidBackupReason.corrupt,
      'unsupported package ${manifest['format']} v${manifest['version']}',
    );
  }

  final photos = <String, Uint8List>{};
  for (final file in archive.files) {
    if (!file.isFile || !file.name.startsWith(_photosFolder)) continue;
    final name = p.posix.basename(file.name);
    final data = file.readBytes();
    if (name.isEmpty || data == null) continue;
    photos[name] = data;
  }

  return BackupPackage(
    database: database,
    photos: photos,
    schemaVersion: manifest['schemaVersion'] as int?,
    sourceDocumentsDir: manifest['documentsDir'] as String?,
  );
}
