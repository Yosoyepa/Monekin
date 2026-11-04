// Journal of a restore in progress (T002, round 4). Before the database is touched, a
// marker is written beside it; the files it replaces are renamed, not deleted, so
// they can be put back whatever fails afterwards, even if the app dies halfway. The
// next start finds the marker and goes back to the state before the restore.
import 'dart:convert';
import 'dart:io';

import 'package:monekin/core/database/backup/database_snapshot.dart';

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

  /// Run before the database is opened: undoes a restore the app did not finish and
  /// removes the temporary files of one that died while preparing. Returns whether
  /// there was a restore to undo.
  static Future<bool> recoverInterrupted(String dbPath) async {
    final journal = RestoreJournal(dbPath);
    final interrupted = journal.isOpen;
    if (interrupted) await journal.rollback();

    for (final suffix in const [
      kRestoreTempSuffix,
      kSnapshotSuffix,
      '$kRestoreMarkerSuffix.new',
    ]) {
      final leftover = File('$dbPath$suffix');
      if (await leftover.exists()) await leftover.delete();
    }
    final staged = Directory('$dbPath$kRestorePhotosSuffix');
    if (await staged.exists()) await staged.delete(recursive: true);
    return interrupted;
  }
}
