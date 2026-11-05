// Safe restore of a copy (T002) in two phases: extract and validate everything in
// temporary files, and only then bring the photos and swap the database. The files it
// replaces are set aside, not deleted, and a journal beside the database lets any
// failure, or a restore the app did not live to finish, go back to the state before
// (see `RestoreJournal`). The app must restart after a restore, because the old
// connection is closed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/database_snapshot.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:monekin/core/database/backup/restore_journal.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:monekin/core/database/services/app-data/app_data_service.dart';
import 'package:monekin/core/utils/logger.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Tables that every version of the database has; the others come with migrations.
const kCoreTables = {'appData', 'accounts', 'transactions'};

/// How often a restore checks whether the background runs have ended.
const kBackgroundPoll = Duration(milliseconds: 200);

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

/// The steps of [BackupRestorer.restore], in order. Tests make one of them fail to
/// prove that every one of them goes back.
enum RestoreStage {
  extract,
  validate,
  stagePhotos,
  keepCurrent,
  journal,
  bringPhotos,
  close,
  setAside,
  swap,
  commit,
}

class BackupRestorer {
  BackupRestorer({
    required this.databasePath,
    required this.documentsDir,
    required this.schemaVersion,
    required this.closeDatabase,
    this.preCopies,
    this.backgroundWait = const Duration(seconds: 60),
    DateTime Function()? now,
    @visibleForTesting this.onStage,
    @visibleForTesting
    Future<void> Function(String source, String target)? snapshot,
  }) : _now = now ?? DateTime.now,
       _snapshot = snapshot ?? snapshotDatabase;

  final Future<String> Function() databasePath;
  final Future<String> Function() documentsDir;
  final int Function() schemaVersion;

  /// Closes the connection of the running app to the database.
  final Future<void> Function() closeDatabase;

  /// Told when the copy of the replaced database is kept, so it can be deleted later.
  final PreCopiesState? preCopies;

  /// How long a restore waits for the background runs that hold the database.
  final Duration backgroundWait;
  final DateTime Function() _now;
  final Future<void> Function(String source, String target) _snapshot;

  /// Called at the start of every step and awaited; a test throws from it to make that
  /// step fail, or runs another operation in it to interleave with the step.
  final FutureOr<void> Function(RestoreStage stage)? onStage;

  /// Restores a v1 (bare database), v2 (zip) or v3 (encrypted) copy in two phases.
  /// A v1 or v2 copy is not encrypted and is refused unless [unencryptedConfirmed].
  /// A v3 copy is opened first with [resolveKey]; a wrong password or a changed file
  /// throws before anything is touched. Then everything is extracted to temporary
  /// files beside the database and validated; only then the photos are brought (never
  /// over an existing one) and the database is swapped.
  ///
  /// If anything throws before the connection is closed, the database, its sidecars
  /// and the photos go back as they were at once. If it throws after the close, the
  /// connection cannot be reopened, so the journal is left and a
  /// [RestoreNeedsRestartException] tells the user to restart: the next start undoes
  /// the restore (`RestoreJournal.recoverInterrupted`). The same happens if the app
  /// dies halfway. After it returns the app must restart.
  Future<void> restore(
    Uint8List bytes, {
    BackupKeyResolver? resolveKey,
    bool unencryptedConfirmed = false,
  }) async {
    if (isEncryptedBackup(bytes)) {
      if (resolveKey == null) {
        throw const InvalidBackupException(
          InvalidBackupReason.passwordRequired,
          'the copy is encrypted',
        );
      }
      bytes = await decryptBackupBytes(bytes, resolveKey);
    } else if (!unencryptedConfirmed) {
      throw const InvalidBackupException(
        InvalidBackupReason.unencrypted,
        'the copy is not encrypted',
      );
    }
    final package = parseBackupPackage(bytes);
    final dbPath = await databasePath();

    // From here to the end nobody else may recover, open or clean up the files.
    final lock = await RestoreLock.acquire(dbPath);
    try {
      await _waitForBackgroundRuns(lock, dbPath);
      await _restoreLocked(package, dbPath, lock);
    } finally {
      await lock.release();
    }
  }

  /// Waits, at most [backgroundWait], until no background run holds the database. The
  /// holder of [lock] beats its file first, so a run that looks at the lock from now on
  /// sees it. Throws [RestoreBusyException] if a run does not end in time.
  Future<void> _waitForBackgroundRuns(RestoreLock lock, String dbPath) async {
    lock.refresh();
    final clock = Stopwatch()..start();
    var announced = false;
    while (true) {
      final runs = await RestoreLock.liveBackgroundRuns(dbPath);
      if (runs == 0) return;
      if (!announced) {
        announced = true;
        Logger.printDebug('Restore waiting for $runs background task(s)');
      }
      if (clock.elapsed >= backgroundWait) throw const RestoreBusyException();
      await Future<void>.delayed(kBackgroundPoll);
    }
  }

  Future<void> _restoreLocked(
    BackupPackage package,
    String dbPath,
    RestoreLock lock,
  ) async {
    final receipts = receiptsDirOf(await documentsDir());
    final tempDb = File(uniqueTempPath(dbPath, kRestoreTempSuffix));
    final stagedPhotos = Directory(
      uniqueTempPath(dbPath, kRestorePhotosSuffix),
    );
    final journal = RestoreJournal(dbPath);

    File? keptCopy;
    var closing = false;
    var committed = false;

    try {
      // Phase 1: extract and validate.
      await onStage?.call(RestoreStage.extract);
      await tempDb.writeAsBytes(package.database, flush: true);

      await onStage?.call(RestoreStage.validate);
      validateDatabaseFile(tempDb.path, schemaVersion: schemaVersion());

      await onStage?.call(RestoreStage.stagePhotos);
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

      // Phase 2: commit. Nothing is deleted until the new database is in place.
      await _waitForBackgroundRuns(lock, dbPath);
      await onStage?.call(RestoreStage.keepCurrent);
      keptCopy = await _keepCurrent(dbPath);

      final toBring = [
        for (final name in package.photos.keys)
          if (!await File(p.join(receipts, name)).exists())
            p.join(receipts, name),
      ];

      await onStage?.call(RestoreStage.journal);
      await journal.begin(
        hadDatabase: await File(dbPath).exists(),
        photos: toBring,
      );

      await onStage?.call(RestoreStage.bringPhotos);
      for (final target in toBring) {
        await File(target).parent.create(recursive: true);
        await File(p.join(stagedPhotos.path, p.basename(target))).copy(target);
      }

      await onStage?.call(RestoreStage.close);
      closing = true;
      await closeDatabase();

      await onStage?.call(RestoreStage.setAside);
      await journal.moveLiveAside();

      await onStage?.call(RestoreStage.swap);
      await tempDb.rename(dbPath);

      await onStage?.call(RestoreStage.commit);
      await journal.commit();
      committed = true;
    } catch (e) {
      if (!committed) {
        if (closing) throw RestoreNeedsRestartException(e);
        await _undo(journal, keptCopy);
      }
      rethrow;
    } finally {
      if (await tempDb.exists()) await tempDb.delete();
      if (await stagedPhotos.exists()) {
        await stagedPhotos.delete(recursive: true);
      }
    }

    // The restore is done; failing to tidy up must not make it look failed. The next
    // start finishes the cleanup from the journal.
    try {
      await journal.finish();
      await prunePreCopies(dbPath, kPreRestoreCopyKind);
      await preCopies?.markCopyKept(_now());
    } catch (e) {
      Logger.printDebug('Restore cleanup left work for the next start: $e');
    }
  }

  /// Keeps what is about to be replaced as a dated copy made by SQLite, so what is
  /// still in the write-ahead log is in it. If the snapshot fails it is tried once
  /// more, and only a database SQLite cannot read at all is copied as it is. Returns
  /// null when there is no database yet.
  Future<File?> _keepCurrent(String dbPath) async {
    final current = File(dbPath);
    if (!await current.exists()) return null;

    final copy = File(newPreCopyPath(dbPath, kPreRestoreCopyKind, _now()));
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await _snapshot(dbPath, copy.path);
        return copy;
      } catch (e) {
        Logger.printDebug(
          'Snapshot $attempt of 2 of the current database failed: '
          '${e.runtimeType}',
        );
        if (await copy.exists()) await copy.delete();
      }
    }
    Logger.printDebug('Keeping the current database as a plain file copy');
    await current.copy(copy.path);
    return copy;
  }

  Future<void> _undo(RestoreJournal journal, File? keptCopy) async {
    try {
      await journal.rollback();
      if (keptCopy != null && await keptCopy.exists()) await keptCopy.delete();
    } catch (e) {
      // The journal stays, and the next start finishes going back.
      Logger.printDebug('Could not undo the restore now: $e');
    }
  }
}

bool _isPlainFileName(String name) =>
    name.isNotEmpty &&
    name != '.' &&
    name != '..' &&
    !name.contains(RegExp(r'[\\/:]'));

/// Restores [bytes] over the database of the running app. The caller has already
/// asked the user to confirm a copy that is not encrypted.
///
/// `AppDB.instance` cannot be opened again once closed, so a failure after the close
/// is reported as [RestoreNeedsRestartException]: the restore is undone by the next
/// start.
Future<void> restoreInApp(Uint8List bytes, BackupKeyResolver? resolveKey) {
  final db = AppDB.instance;
  return BackupRestorer(
    databasePath: () => db.databasePath,
    documentsDir: () async => (await getApplicationDocumentsDirectory()).path,
    schemaVersion: () => db.schemaVersion,
    closeDatabase: db.close,
    preCopies: PreCopiesState.inSupportDir(),
  ).restore(bytes, resolveKey: resolveKey, unencryptedConfirmed: true);
}
