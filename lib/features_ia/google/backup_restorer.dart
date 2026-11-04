// Safe restore of a Drive copy (T002) in two phases: extract and validate everything in
// temporary files, and only then bring the photos and swap the database.
// The app must restart afterwards, because the old connection is closed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:monekin/core/database/services/app-data/app_data_service.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Tables that every version of the database has; the others come with migrations.
const kCoreTables = {'appData', 'accounts', 'transactions'};

/// Checks the database at [path] is a healthy Monekin database that this app can open.
/// Throws [InvalidBackupException] otherwise.
void validateDatabaseFile(String path, {required int schemaVersion}) {
  final Database db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
  } catch (e) {
    throw InvalidBackupException(InvalidBackupReason.corrupt, '$e');
  }

  try {
    final check = db.select('PRAGMA integrity_check');
    if (check.length != 1 || check.first.values.first != 'ok') {
      throw const InvalidBackupException(
        InvalidBackupReason.corrupt,
        'integrity_check failed',
      );
    }

    final tables = {
      for (final row in db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name'],
    };
    if (!tables.containsAll(kCoreTables)) {
      throw const InvalidBackupException(
        InvalidBackupReason.corrupt,
        'the database lacks core tables',
      );
    }

    final rows = db.select(
      'SELECT appDataValue FROM appData WHERE appDataKey = ?',
      [AppDataKey.dbVersion.name],
    );
    final version = rows.isEmpty
        ? null
        : int.tryParse('${rows.first['appDataValue']}');
    if (version == null) {
      throw const InvalidBackupException(
        InvalidBackupReason.corrupt,
        'no schema version in appData',
      );
    }
    if (version > schemaVersion) {
      throw InvalidBackupException(
        InvalidBackupReason.newerSchema,
        'copy v$version, app v$schemaVersion',
      );
    }
  } on InvalidBackupException {
    rethrow;
  } catch (e) {
    throw InvalidBackupException(InvalidBackupReason.corrupt, '$e');
  } finally {
    db.close();
  }
}

/// Writes [bytes] to [tempPath], validates them and removes the file again.
Future<void> validateDatabaseBytes(
  Uint8List bytes, {
  required String tempPath,
  required int schemaVersion,
}) async {
  final file = File(tempPath);
  await file.writeAsBytes(bytes, flush: true);
  try {
    validateDatabaseFile(tempPath, schemaVersion: schemaVersion);
  } finally {
    if (await file.exists()) await file.delete();
  }
}

String? _relocated(String oldPath, Set<String> names, String receiptsDir) {
  final name = oldPath.split(RegExp(r'[\\/]')).last;
  return names.contains(name) ? p.join(receiptsDir, name) : null;
}

/// Points the photo paths stored in the database at [path] to [receiptsDir].
void relocatePhotoPaths(
  String path, {
  required Set<String> photoNames,
  required String receiptsDir,
}) {
  final db = sqlite3.open(path);
  try {
    bool hasTable(String name) => db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    ).isNotEmpty;

    db.execute('BEGIN');
    try {
      if (hasTable('transactionAttachments')) {
        final update = db.prepare(
          'UPDATE transactionAttachments SET filePath = ? WHERE id = ?',
        );
        for (final row in db.select(
          'SELECT id, filePath FROM transactionAttachments',
        )) {
          final next = _relocated(
            row['filePath'] as String,
            photoNames,
            receiptsDir,
          );
          if (next != null) update.execute([next, row['id']]);
        }
        update.close();
      }

      if (hasTable('aiInboxItems')) {
        final update = db.prepare(
          'UPDATE aiInboxItems SET attachmentsJson = ? WHERE id = ?',
        );
        for (final row in db.select(
          'SELECT id, attachmentsJson FROM aiInboxItems '
          'WHERE attachmentsJson IS NOT NULL',
        )) {
          final decoded = jsonDecode(row['attachmentsJson'] as String);
          if (decoded is! List) continue;
          final paths = [
            for (final item in decoded)
              item is String
                  ? (_relocated(item, photoNames, receiptsDir) ?? item)
                  : item,
          ];
          update.execute([jsonEncode(paths), row['id']]);
        }
        update.close();
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    db.close();
  }
}

class BackupRestorer {
  BackupRestorer({
    required this.databasePath,
    required this.documentsDir,
    required this.schemaVersion,
    required this.closeDatabase,
    this.preCopies,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<String> Function() databasePath;
  final Future<String> Function() documentsDir;
  final int Function() schemaVersion;

  /// Closes the connection of the running app to the database.
  final Future<void> Function() closeDatabase;

  /// Told when the copy of the replaced database is kept, so it can be deleted later.
  final PreCopiesState? preCopies;
  final DateTime Function() _now;

  /// Restores a v1 (bare database), v2 (zip) or v3 (encrypted) copy in two phases.
  /// A v3 copy is opened first with [resolveKey]; a wrong password or a changed file
  /// throws before anything is touched. Then everything is extracted to temporary
  /// files beside the database and validated; only then the photos are brought (never
  /// over an existing one) and the database is swapped. If anything throws, the
  /// database and the photos stay as they were; after it returns the app must restart.
  Future<void> restore(Uint8List bytes, {BackupKeyResolver? resolveKey}) async {
    if (isEncryptedBackup(bytes)) {
      if (resolveKey == null) {
        throw const InvalidBackupException(
          InvalidBackupReason.passwordRequired,
          'the copy is encrypted',
        );
      }
      bytes = await decryptBackupBytes(bytes, resolveKey);
    }
    final package = parseBackupPackage(bytes);
    final dbPath = await databasePath();
    final receipts = receiptsDirOf(await documentsDir());
    final tempDb = File('$dbPath.restore_tmp');
    final stagedPhotos = Directory('$dbPath.restore_photos');
    final broughtPhotos = <File>[];

    try {
      // Phase 1: extract and validate.
      await tempDb.writeAsBytes(package.database, flush: true);
      validateDatabaseFile(tempDb.path, schemaVersion: schemaVersion());

      if (await stagedPhotos.exists()) {
        await stagedPhotos.delete(recursive: true);
      }
      for (final photo in package.photos.entries) {
        if (!_isPlainFileName(photo.key)) {
          throw const InvalidBackupException(
            InvalidBackupReason.corrupt,
            'unsafe photo name',
          );
        }
        final staged = File(p.join(stagedPhotos.path, photo.key));
        await staged.create(recursive: true);
        await staged.writeAsBytes(photo.value, flush: true);
      }
      if (package.photos.isNotEmpty) {
        relocatePhotoPaths(
          tempDb.path,
          photoNames: package.photos.keys.toSet(),
          receiptsDir: receipts,
        );
        validateDatabaseFile(tempDb.path, schemaVersion: schemaVersion());
      }

      // Phase 2: commit.
      final current = File(dbPath);
      if (await current.exists()) {
        await current.copy(
          p.join(
            p.dirname(dbPath),
            '${p.basenameWithoutExtension(dbPath)}.$kPreRestoreCopyKind.db',
          ),
        );
        await preCopies?.markCopyKept(_now());
      }

      for (final photo in package.photos.keys) {
        final target = File(p.join(receipts, photo));
        if (await target.exists()) continue;
        await target.parent.create(recursive: true);
        broughtPhotos.add(target);
        await File(p.join(stagedPhotos.path, photo)).copy(target.path);
      }

      await closeDatabase();
      for (final suffix in const ['-wal', '-shm', '-journal']) {
        final sidecar = File('$dbPath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      await tempDb.rename(dbPath);
    } catch (_) {
      for (final photo in broughtPhotos) {
        if (await photo.exists()) await photo.delete();
      }
      rethrow;
    } finally {
      if (await tempDb.exists()) await tempDb.delete();
      if (await stagedPhotos.exists()) {
        await stagedPhotos.delete(recursive: true);
      }
    }
  }
}

bool _isPlainFileName(String name) =>
    name.isNotEmpty &&
    name != '.' &&
    name != '..' &&
    !name.contains(RegExp(r'[\\/:]'));
