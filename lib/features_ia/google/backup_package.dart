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

/// Largest copy that is downloaded or read at all.
const kMaxBackupBytes = 600 * 1024 * 1024;

/// Limits on a Drive copy's zip. They are checked on the declared sizes, before any
/// entry is extracted.
const kMaxZipEntries = 5000;
const kMaxZipEntryBytes = 256 * 1024 * 1024;
const kMaxZipTotalBytes = 512 * 1024 * 1024;

/// `<documents>/finanzas_ia/receipts`, where `saveReceiptPhoto` keeps the photos.
String receiptsDirOf(String documentsDir) =>
    p.join(documentsDir, 'finanzas_ia', 'receipts');

enum InvalidBackupReason {
  corrupt,
  newerSchema,
  wrongPassword,
  tampered,
  passwordRequired,
}

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

InvalidBackupException _corrupt(String detail) =>
    InvalidBackupException(InvalidBackupReason.corrupt, detail);

/// Gathers a download, giving up as soon as it goes over [maxBytes].
Future<Uint8List> collectCapped(
  Stream<List<int>> chunks, {
  int maxBytes = kMaxBackupBytes,
}) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in chunks) {
    if (builder.length + chunk.length > maxBytes) {
      throw _corrupt('the copy is over $maxBytes bytes');
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Whether a stored entry name could write outside the folder it is extracted to.
bool _isUnsafeEntryName(String name) =>
    name.isEmpty ||
    name.contains(r'\') ||
    name.contains(':') ||
    name.contains('\u0000') ||
    name.startsWith('/') ||
    name.split('/').any((part) => part == '..' || part == '.');

/// Reads the central directory of the zip in [bytes] without decompressing anything
/// and rejects it if it breaks a limit or declares anything unsafe: too many entries
/// or declared bytes, encrypted or zip64 entries, symbolic links, repeated names, and
/// names with `\`, `..`, `:` or an absolute path. Returns the entry names.
List<String> _vetZipDirectory(Uint8List bytes) {
  const endSignature = 0x06054b50;
  const entrySignature = 0x02014b50;
  const endSize = 22;
  const entryHeaderSize = 46;

  final data = ByteData.sublistView(bytes);

  var end = -1;
  final lowest = bytes.length - endSize - 0xffff;
  for (var i = bytes.length - endSize; i >= 0 && i >= lowest; i--) {
    if (data.getUint32(i, Endian.little) == endSignature) {
      end = i;
      break;
    }
  }
  if (end < 0) throw _corrupt('no zip directory');

  final entries = data.getUint16(end + 10, Endian.little);
  final directorySize = data.getUint32(end + 12, Endian.little);
  final directoryOffset = data.getUint32(end + 16, Endian.little);
  if (entries == 0xffff ||
      directorySize == 0xffffffff ||
      directoryOffset == 0xffffffff) {
    throw _corrupt('zip64 is not supported');
  }
  if (entries > kMaxZipEntries) {
    throw _corrupt('more than $kMaxZipEntries entries');
  }
  if (directoryOffset + directorySize > end) {
    throw _corrupt('the zip directory is out of bounds');
  }

  final names = <String>{};
  var total = 0;
  var position = directoryOffset;
  for (var i = 0; i < entries; i++) {
    if (position + entryHeaderSize > end ||
        data.getUint32(position, Endian.little) != entrySignature) {
      throw _corrupt('damaged zip directory');
    }
    final flags = data.getUint16(position + 8, Endian.little);
    final method = data.getUint16(position + 10, Endian.little);
    final compressed = data.getUint32(position + 20, Endian.little);
    final size = data.getUint32(position + 24, Endian.little);
    final nameLength = data.getUint16(position + 28, Endian.little);
    final extraLength = data.getUint16(position + 30, Endian.little);
    final commentLength = data.getUint16(position + 32, Endian.little);
    final attributes = data.getUint32(position + 38, Endian.little);
    final localOffset = data.getUint32(position + 42, Endian.little);

    final nameStart = position + entryHeaderSize;
    final next = nameStart + nameLength + extraLength + commentLength;
    if (next > end) throw _corrupt('damaged zip directory');

    final nameBytes = Uint8List.sublistView(
      bytes,
      nameStart,
      nameStart + nameLength,
    );
    final String name;
    try {
      name = flags & 0x800 != 0
          ? utf8.decode(nameBytes)
          : latin1.decode(nameBytes);
    } on FormatException {
      throw _corrupt('an entry name is not valid text');
    }

    if (_isUnsafeEntryName(name)) throw _corrupt('unsafe entry name');
    if (!names.add(name)) throw _corrupt('repeated entry name');
    if (flags & 1 != 0) throw _corrupt('$name is encrypted');
    if (method != 0 && method != 8) {
      throw _corrupt('$name uses an unknown method');
    }
    if (compressed == 0xffffffff ||
        size == 0xffffffff ||
        localOffset == 0xffffffff) {
      throw _corrupt('zip64 is not supported');
    }
    if (localOffset >= directoryOffset) throw _corrupt('damaged zip directory');
    if ((attributes >> 16) & 0xf000 == 0xa000) {
      throw _corrupt('$name is a symbolic link');
    }

    if (size > kMaxZipEntryBytes) {
      throw _corrupt('$name declares $size bytes');
    }
    total += size;
    if (total > kMaxZipTotalBytes) {
      throw _corrupt('uncompressed total over $kMaxZipTotalBytes bytes');
    }

    position = next;
  }

  return names.toList();
}

/// Decodes a zip; replaced in tests to prove nothing is decompressed before the
/// directory is vetted.
typedef ZipDecode = Archive Function(Uint8List bytes);

Archive _decodeZip(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

/// Reads a Drive copy, whatever its version. A zip is vetted from its central
/// directory before [decode] is called.
BackupPackage parseBackupPackage(
  Uint8List bytes, {
  ZipDecode decode = _decodeZip,
}) {
  if (bytes.length > kMaxBackupBytes) {
    throw _corrupt('the copy is over $kMaxBackupBytes bytes');
  }
  if (!_isZip(bytes)) return BackupPackage(database: bytes);

  final names = _vetZipDirectory(bytes);

  final Archive archive;
  try {
    archive = decode(bytes);
  } catch (e) {
    throw InvalidBackupException(InvalidBackupReason.corrupt, '$e');
  }
  if (archive.files.length != names.length) {
    throw _corrupt('the zip does not match its directory');
  }

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
