// Consistent copy of the live database (T002, round 4). Reading the file while the app
// runs misses what is still in the write-ahead log, so a copy is always made by
// SQLite itself with `VACUUM INTO`.
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

/// Suffix of the temporary snapshot kept beside the database while it is read.
const kSnapshotSuffix = '.snapshot_tmp';

final _random = Random.secure();

/// A path beside the database for a temporary file or folder of [suffix], with a
/// random tail so two operations never share one and one never deletes the other's.
String uniqueTempPath(String dbPath, String suffix) {
  final tail = List.generate(
    8,
    (_) => _random.nextInt(16).toRadixString(16),
  ).join();
  return '$dbPath$suffix.$tail';
}

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
