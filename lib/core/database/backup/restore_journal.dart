// Journal of a restore in progress (T002, round 4). Before the database is touched, a
// marker is written beside it; the files it replaces are renamed, not deleted, so
// they can be put back whatever fails afterwards, even if the app dies halfway. The
// next start finds the marker and goes back to the state before the restore.
import 'dart:convert';
import 'dart:io';

import 'package:monekin/core/database/backup/database_snapshot.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:monekin/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// A temporary file is an orphan, and may be deleted, only after this long.
const kOrphanTempAge = Duration(minutes: 10);

const kRestoreMarkerSuffix = '.restore_marker';
const kRestoreTempSuffix = '.restore_tmp';
const kRestorePhotosSuffix = '.restore_photos';
const kRestoreAsideSuffix = '.restore_bak';

/// The database file and its sidecars; the main file goes last so a half-done move
/// never leaves a sidecar without its database.
const _parts = ['-wal', '-shm', '-journal', ''];

class RestoreJournal {
  RestoreJournal(this.dbPath);

  final String dbPath;

  File get _marker => File('$dbPath$kRestoreMarkerSuffix');

  File _live(String part) => File('$dbPath$part');

  File _aside(String part) => File('$dbPath$part$kRestoreAsideSuffix');

  /// Whether a restore was started and neither finished nor undone.
  bool get isOpen => _marker.existsSync();

  /// Whether the files beside [dbPath] show a restore in flight: its marker, or a
  /// database set aside with no live one. Reads only the file system, never opens
  /// the database, and holds across isolates and processes.
  static bool leftInFlux(String dbPath) =>
      File('$dbPath$kRestoreMarkerSuffix').existsSync() ||
      File('$dbPath$kRestoreMarkerSuffix.new').existsSync() ||
      (!File(dbPath).existsSync() &&
          File('$dbPath$kRestoreAsideSuffix').existsSync());

  Future<void> _writeMarker(Map<String, Object?> data) async {
    final next = File('${_marker.path}.new');
    await next.writeAsString(jsonEncode(data), flush: true);
    await next.rename(_marker.path);
  }

  /// Opens the journal. [photos] are the files the restore is about to create; they
  /// are the only ones deleted if it is undone.
  Future<void> begin({
    required bool hadDatabase,
    required List<String> photos,
  }) => _writeMarker({
    'phase': 'swap',
    'hadDatabase': hadDatabase,
    'photos': photos,
  });

  /// Moves the database and its sidecars out of the way, keeping them.
  Future<void> moveLiveAside() async {
    for (final part in _parts) {
      final live = _live(part);
      if (await live.exists()) {
        final aside = _aside(part);
        if (await aside.exists()) await aside.delete();
        await live.rename(aside.path);
      }
    }
  }

  /// The new database is in place: from now on the restore is not undone.
  Future<void> commit() async {
    final info = await _read();
    await _writeMarker({...info, 'phase': 'committed'});
  }

  /// Deletes what a finished restore left behind.
  Future<void> finish() async {
    for (final part in _parts) {
      final aside = _aside(part);
      if (await aside.exists()) await aside.delete();
    }
    if (await _marker.exists()) await _marker.delete();
  }

  Future<Map<String, Object?>> _read() async {
    try {
      final decoded = jsonDecode(await _marker.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } on FileSystemException {
      // handled below
    } on FormatException {
      // handled below
    }
    // An unreadable marker: only put back what was set aside.
    return {'phase': 'swap', 'hadDatabase': true, 'photos': <String>[]};
  }

  /// Puts the database, the sidecars and the photos back as they were before the
  /// restore. Safe to run again if it was interrupted.
  Future<void> rollback() async {
    if (!_marker.existsSync()) return;
    final info = await _read();

    if (info['phase'] == 'committed') {
      await finish();
      return;
    }

    if (info['hadDatabase'] == false) {
      for (final part in _parts) {
        final live = _live(part);
        if (await live.exists()) await live.delete();
      }
    } else {
      for (final part in _parts) {
        final aside = _aside(part);
        if (!await aside.exists()) continue;
        final live = _live(part);
        if (await live.exists()) await live.delete();
        await aside.rename(live.path);
      }
    }

    final photos = info['photos'];
    if (photos is List) {
      for (final path in photos.whereType<String>()) {
        final photo = File(path);
        if (await photo.exists()) await photo.delete();
      }
    }
    await _marker.delete();
  }

  /// Run before the database is opened. It takes the [RestoreLock] without blocking:
  /// if a restore holds it, that restore is alive and nothing is touched
  /// ([RestoreRecovery.inProgress]), though it keeps trying for [wait] first. With
  /// the lock it undoes a restore the app did not finish, removes the holder files and
  /// flags of processes that no longer live and the orphan temporary files (see
  /// [kOrphanTempAge]) and, if the app has no database but the one a restore set aside
  /// or a copy kept before it, puts that back.
  static Future<RestoreRecovery> recoverInterrupted(
    String dbPath, {
    Duration wait = Duration.zero,
    DateTime Function()? now,
  }) async {
    // Without announcing it: the holder file of a live restore is not this recovery's to touch.
    final lock = await RestoreLock.tryAcquireFor(dbPath, wait, announce: false);
    if (lock == null) return RestoreRecovery.inProgress;
    try {
      await RestoreLock.removeForeignMarks(dbPath);
      final journal = RestoreJournal(dbPath);
      var result = RestoreRecovery.nothing;
      if (journal.isOpen) {
        await journal.rollback();
        result = RestoreRecovery.undone;
      }

      final marker = File('$dbPath$kRestoreMarkerSuffix.new');
      if (await marker.exists()) await marker.delete();
      await _removeOrphans(dbPath, (now ?? DateTime.now)());

      if (await _bringBackMissingDatabase(dbPath) &&
          result == RestoreRecovery.nothing) {
        result = RestoreRecovery.restoredMissing;
      }
      return result;
    } finally {
      await lock.release();
    }
  }

  /// Deletes the temporary files and folders beside the database that no operation
  /// owns: the lock is ours, and they are older than [kOrphanTempAge].
  static Future<void> _removeOrphans(String dbPath, DateTime now) async {
    final dir = Directory(p.dirname(dbPath));
    if (!await dir.exists()) return;
    final base = p.basename(dbPath);
    final prefixes = [
      '$base$kRestoreTempSuffix',
      '$base$kSnapshotSuffix',
      '$base$kRestorePhotosSuffix',
    ];
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (!prefixes.any(name.startsWith)) continue;
      final stat = await entity.stat();
      if (now.difference(stat.modified) < kOrphanTempAge) continue;
      try {
        await entity.delete(recursive: true);
      } on FileSystemException catch (e) {
        Logger.printDebug('Could not remove a leftover temporary file: $e');
      }
    }
  }

  /// If the database file is missing, puts back the one a restore set aside or, failing
  /// that, the latest healthy copy kept before a restore or an import. Returns whether
  /// it did.
  static Future<bool> _bringBackMissingDatabase(String dbPath) async {
    if (await File(dbPath).exists()) return false;

    // Without its database a log file is only a hazard; the set-aside ones replace it.
    final asideMain = File('$dbPath$kRestoreAsideSuffix');
    final hasAside = await asideMain.exists();
    for (final part in _parts) {
      final live = File('$dbPath$part');
      final aside = File('$dbPath$part$kRestoreAsideSuffix');
      if (part.isNotEmpty && await live.exists()) await live.delete();
      if (hasAside && await aside.exists()) await aside.rename(live.path);
    }
    if (hasAside) {
      Logger.printDebug('The database was missing: put back the one set aside');
      return true;
    }

    final copies = [
      for (final kind in const [kPreRestoreCopyKind, kPreImportCopyKind])
        ...preCopyFiles(dbPath, kind),
    ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final copy in copies) {
      final staged = File(uniqueTempPath(dbPath, kRestoreTempSuffix));
      try {
        await copy.copy(staged.path);
        if (!_isHealthy(staged.path)) {
          await staged.delete();
          continue;
        }
        await staged.rename(dbPath);
        Logger.printDebug('The database was missing: put back a kept copy');
        return true;
      } on FileSystemException catch (e) {
        Logger.printDebug('Could not put back a kept copy: $e');
        if (await staged.exists()) await staged.delete();
      }
    }
    return false;
  }

  static bool _isHealthy(String path) {
    try {
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        final check = db.select('PRAGMA integrity_check');
        return check.length == 1 &&
            check.first.values.first == 'ok' &&
            db
                .select(
                  "SELECT 1 FROM sqlite_master WHERE type = 'table' "
                  "AND name = 'accounts'",
                )
                .isNotEmpty;
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }
}

/// What [RestoreJournal.recoverInterrupted] found.
enum RestoreRecovery {
  /// Nothing to do.
  nothing,

  /// A restore the app did not finish was undone (or its cleanup was finished).
  undone,

  /// There was no database and the previous one was put back.
  restoredMissing,

  /// A restore is alive and holds the lock: nothing was touched.
  inProgress,
}
