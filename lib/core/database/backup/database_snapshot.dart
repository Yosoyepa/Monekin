// Consistent copy of the live database (T002, round 4). Reading the file while the app
// runs misses what is still in the write-ahead log, so a copy is always made by
// SQLite itself with `VACUUM INTO`.
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

/// Suffix of the temporary snapshot kept beside the database while it is read.
const kSnapshotSuffix = '.snapshot_tmp';

/// Writes a snapshot of the database at [sourcePath] to [targetPath] (replacing it).
/// The snapshot holds everything committed so far, including what is still in the
/// write-ahead log, and is a plain database file with no sidecars.
void snapshotDatabaseSync(String sourcePath, String targetPath) {
  if (!File(sourcePath).existsSync()) {
    throw FileSystemException('the database does not exist', sourcePath);
  }
  final target = File(targetPath);
  if (target.existsSync()) target.deleteSync();

  // Read-only, so closing this connection never checkpoints or removes the log files
  // of a database the app still has open.
  final db = sqlite3.open(sourcePath, mode: OpenMode.readOnly);
  try {
    db.execute('PRAGMA busy_timeout = 10000');
    db.execute('VACUUM INTO ?', [targetPath]);
  } finally {
    db.close();
  }
}

/// Same as [snapshotDatabaseSync], off the main isolate because it copies the whole
/// database.
Future<void> snapshotDatabase(String sourcePath, String targetPath) =>
    Isolate.run(() => snapshotDatabaseSync(sourcePath, targetPath));
