// Safe restore of a Drive copy (T002): validate on a temporary file, bring the photos, swap the database.
// The app must restart afterwards, because the old connection is closed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:monekin/core/database/services/app-data/app_data_service.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

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
  });

  final Future<String> Function() databasePath;
  final Future<String> Function() documentsDir;
  final int Function() schemaVersion;

  /// Closes the connection of the running app to the database.
  final Future<void> Function() closeDatabase;

  /// Restores a v1 (bare database) or v2 (zip) copy. When it throws before the swap,
  /// the current database was not touched; after it returns the app must restart.
  Future<void> restore(Uint8List bytes) async {
    final package = parseBackupPackage(bytes);
    final dbPath = await databasePath();
    final docs = await documentsDir();
    final receipts = receiptsDirOf(docs);
    final temp = File('$dbPath.restore_tmp');

    try {
      await temp.writeAsBytes(package.database, flush: true);
      validateDatabaseFile(temp.path, schemaVersion: schemaVersion());

      if (package.photos.isNotEmpty) {
        await Directory(receipts).create(recursive: true);
        for (final photo in package.photos.entries) {
          await File(
            p.join(receipts, photo.key),
          ).writeAsBytes(photo.value, flush: true);
        }
        relocatePhotoPaths(
          temp.path,
          photoNames: package.photos.keys.toSet(),
          receiptsDir: receipts,
        );
      }

      final current = File(dbPath);
      if (await current.exists()) {
        await current.copy(
          p.join(
            p.dirname(dbPath),
            '${p.basenameWithoutExtension(dbPath)}.pre_restore_backup.db',
          ),
        );
      }

      await closeDatabase();
      for (final suffix in const ['-wal', '-shm', '-journal']) {
        final sidecar = File('$dbPath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      await temp.rename(dbPath);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }
}
