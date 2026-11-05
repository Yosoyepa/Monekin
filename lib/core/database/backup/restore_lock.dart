// Exclusive lock of a restore (T002, round 5). A restore, and the recovery that runs
// every time the database is opened, must never work at the same time: the recovery
// of a restore that is still alive would delete its marker and its temporary files.
// The lock is held across isolates and processes, so the background tasks, which open
// the database in their own isolate, honour it too.
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Name of the lock file, beside the database.
const kRestoreLockName = 'restore.lock';

/// How often a holder refreshes its file, and how old that file may be to still count.
const kHeldBeat = Duration(seconds: 5);
const kHeldFresh = Duration(seconds: 30);

/// The lock is busy for longer than a restore waits for it.
class RestoreBusyException implements Exception {
  const RestoreBusyException();

  @override
  String toString() => 'RestoreBusyException: another restore holds the lock';
}

/// Two locks in one. A byte-range lock on [kRestoreLockName] excludes other
/// processes; on Android those locks belong to the whole process, so two isolates of
/// the app (the UI and WorkManager) would both get it. A SQLite exclusive transaction
/// on a second file, which SQLite keeps per connection even inside one process,
/// excludes them.
///
/// Whether the WorkManager engine, another isolate group of the same process, sees
/// those locks was not established (E004 round 7). So that the check does not depend
/// on it, the holder also keeps a file beside the lock whose modification time it
/// refreshes while it holds on: [isHeld] reads it.
class RestoreLock {
  RestoreLock._(this._file, this._guard, this._heldPath) {
    if (_heldPath == null) return;
    _touchHeld();
    _beat = Timer.periodic(kHeldBeat, (_) => _touchHeld());
  }

  final RandomAccessFile _file;
  final Database _guard;
  final String? _heldPath;
  Timer? _beat;
  var _released = false;

  static String lockPath(String dbPath) =>
      p.join(p.dirname(dbPath), kRestoreLockName);

  /// Beside the lock: exists while a holder keeps beating.
  static String heldPath(String dbPath) => '${lockPath(dbPath)}.held';

  void _touchHeld() {
    try {
      File(_heldPath!).writeAsStringSync(DateTime.now().toIso8601String());
    } on FileSystemException {
      // a missed beat only matters if the next ones fail too
    }
  }

  /// Takes the lock without waiting. Null when someone else holds it. With
  /// [announce] false it leaves no trace for [isHeld] (used by [isHeld] itself).
  static Future<RestoreLock?> tryAcquire(
    String dbPath, {
    bool announce = true,
  }) async {
    final path = lockPath(dbPath);
    await Directory(p.dirname(path)).create(recursive: true);

    final Database guard;
    try {
      guard = sqlite3.open('$path.guard');
    } on SqliteException {
      return null;
    }
    try {
      guard.execute('PRAGMA busy_timeout = 0');
      guard.execute('BEGIN EXCLUSIVE');
    } on SqliteException {
      guard.close();
      return null;
    }

    final file = await File(path).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
    } on FileSystemException {
      await file.close();
      _closeGuard(guard);
      return null;
    }
    return RestoreLock._(file, guard, announce ? heldPath(dbPath) : null);
  }

  /// Takes the lock, trying again every [poll] for up to [timeout]. Throws
  /// [RestoreBusyException] if it never frees up.
  static Future<RestoreLock> acquire(
    String dbPath, {
    Duration timeout = const Duration(seconds: 30),
    Duration poll = const Duration(milliseconds: 100),
  }) async {
    final lock = await tryAcquireFor(dbPath, timeout, poll: poll);
    if (lock == null) throw const RestoreBusyException();
    return lock;
  }

  /// Like [tryAcquire], but keeps trying for [wait].
  static Future<RestoreLock?> tryAcquireFor(
    String dbPath,
    Duration wait, {
    Duration poll = const Duration(milliseconds: 100),
  }) async {
    final deadline = DateTime.now().add(wait);
    while (true) {
      final lock = await tryAcquire(dbPath);
      if (lock != null || !DateTime.now().isBefore(deadline)) return lock;
      await Future<void>.delayed(poll);
    }
  }

  /// Whether a restore or a recovery holds the lock right now; takes nothing.
  static Future<bool> isHeld(String dbPath, {DateTime Function()? now}) async {
    try {
      final age = (now ?? DateTime.now)().difference(
        File(heldPath(dbPath)).lastModifiedSync(),
      );
      // A file dated ahead of the clock (the clock went back) stops counting too.
      if (age < kHeldFresh && age > -kHeldFresh) return true;
    } on FileSystemException {
      // no holder file, or its holder released it just now
    }
    final lock = await tryAcquire(dbPath, announce: false);
    if (lock == null) return true;
    await lock.release();
    return false;
  }

  static void _closeGuard(Database guard) {
    try {
      guard.execute('ROLLBACK');
    } on SqliteException {
      // closing releases it anyway
    }
    guard.close();
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    _beat?.cancel();
    if (_heldPath != null) {
      try {
        File(_heldPath).deleteSync();
      } on FileSystemException {
        // a stale file stops counting after [kHeldFresh]
      }
    }
    try {
      await _file.unlock();
    } on FileSystemException {
      // closing releases it anyway
    }
    await _file.close();
    _closeGuard(_guard);
  }
}
