// Exclusive lock of a restore (T002, round 5). A restore, and the recovery that runs
// every time the database is opened, must never work at the same time: the recovery
// of a restore that is still alive would delete its marker and its temporary files.
// The lock is held across isolates and processes, so the background tasks, which open
// the database in their own isolate, honour it too.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Name of the lock file, beside the database.
const kRestoreLockName = 'restore.lock';

/// The lock is busy for longer than a restore waits for it.
class RestoreBusyException implements Exception {
  const RestoreBusyException();

  @override
  String toString() => 'RestoreBusyException: another restore holds the lock';
}

String? _token;

/// This process, as the holder file and the flags name it: `pid:starttime`, where the
/// starttime is field 22 of /proc/self/stat (when the process started, in clock ticks
/// since boot). Where there is no /proc (Windows, the tests) it is the pid alone.
/// Computed once per isolate.
String processToken() => _token ??= _readProcessToken();

String _readProcessToken() {
  final start = _starttimeOfSelf();
  return start == null ? '$pid' : '$pid:$start';
}

int? _starttimeOfSelf() {
  try {
    return parseStarttime(File('/proc/self/stat').readAsStringSync());
  } on FileSystemException {
    return null;
  }
}

/// The starttime in a `/proc/<pid>/stat` line, which is field 22. The command name is in
/// parentheses and may hold spaces and `)`, so the count starts after the last `)`: the
/// first field after it is field 3.
int? parseStarttime(String stat) {
  final end = stat.lastIndexOf(')');
  if (end < 0 || end + 2 > stat.length) return null;
  final fields = stat.substring(end + 2).split(' ');
  return fields.length > 19 ? int.tryParse(fields[19]) : null;
}

/// Whether [token], read from a holder file or a flag, belongs to the process [ours]: the
/// same pid, and the same starttime when both tokens carry one.
bool isOwnToken(String token, String ours) {
  final theirs = token.split(':');
  final mine = ours.split(':');
  if (theirs.first != mine.first) return false;
  if (theirs.length > 1 && mine.length > 1) return theirs[1] == mine[1];
  return true;
}

/// Writes this process's token to [path] in one step: a temporary file beside it, renamed
/// over it, so a reader never sees the file half written. Its name starts with a dot, so
/// it is never taken for a flag.
void _writeToken(String path) {
  final tmp = File(p.join(p.dirname(path), '.${p.basename(path)}.tmp'));
  tmp.writeAsStringSync(processToken(), flush: true);
  try {
    tmp.renameSync(path);
  } on FileSystemException {
    _deleteQuietly(tmp.path);
    rethrow;
  }
}

/// The token in the file at [path], or null when the file cannot be read: it is gone, or
/// something stops the read. See [_isPresent] to tell the two apart.
String? _readToken(String path) {
  try {
    return File(path).readAsStringSync().trim();
  } on FileSystemException {
    return null;
  }
}

/// Whether anything is at [path]. A mark that is there but cannot be read counts as
/// alive: an unknown mark must never let a restore through (fv7).
bool _isPresent(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) !=
    FileSystemEntityType.notFound;

void _deleteQuietly(String path) {
  try {
    File(path).deleteSync();
  } on FileSystemException {
    // gone already, or it cannot be deleted now
  }
}

/// Two locks in one. A byte-range lock on [kRestoreLockName] excludes other
/// processes; on Android those locks belong to the whole process, so two isolates of
/// the app (the UI and WorkManager) would both get it. A SQLite exclusive transaction
/// on a second file, which SQLite keeps per connection even inside one process,
/// excludes them.
///
/// Whether the WorkManager engine, another isolate group of the same process, sees
/// those locks was not established (E004 round 7). So that the check does not depend
/// on it, the holder also keeps a file beside the lock that names its process: [isHeld]
/// reads it. Nothing is judged by its date: a file counts while its process lives.
class RestoreLock {
  RestoreLock._(this._file, this._guard, this._heldPath) {
    final held = _heldPath;
    if (held == null) return;
    try {
      _writeToken(held);
    } on FileSystemException {
      // Without the file the checks fall back to the lock itself, which excludes too.
    }
  }

  final RandomAccessFile _file;
  final Database _guard;
  final String? _heldPath;
  var _released = false;

  static String lockPath(String dbPath) =>
      p.join(p.dirname(dbPath), kRestoreLockName);

  /// Beside the lock: names the process that holds it.
  static String heldPath(String dbPath) => '${lockPath(dbPath)}.held';

  /// Takes the lock without waiting. Null when someone else holds it. With
  /// [announce] false it leaves no trace for [isHeld] (used by [isHeld] itself and by
  /// the recovery, which must not touch the file of a live restore).
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
    bool announce = true,
  }) async {
    final deadline = DateTime.now().add(wait);
    while (true) {
      final lock = await tryAcquire(dbPath, announce: announce);
      if (lock != null || !DateTime.now().isBefore(deadline)) return lock;
      await Future<void>.delayed(poll);
    }
  }

  /// Whether a restore or a recovery holds the lock right now; takes nothing. A holder
  /// file of this process counts, whatever its date, and so does one that is there but
  /// cannot be read. One of another process belongs to a process that no longer lives: it
  /// does not count. It is not deleted here, because a restore may be renaming its own
  /// file over it right now; the recovery of the app removes it
  /// ([removeForeignMarks]).
  static Future<bool> isHeld(String dbPath) async {
    final held = heldPath(dbPath);
    final token = _readToken(held);
    if (token == null && _isPresent(held)) return true;
    if (token != null && isOwnToken(token, processToken())) return true;
    final lock = await tryAcquire(dbPath, announce: false);
    if (lock == null) return true;
    await lock.release();
    return false;
  }

  /// How many background runs hold the database: the flags beside the lock that belong
  /// to this process, and those that are there but cannot be read. The others belong to
  /// processes that no longer live: they are deleted and do not count. Flag names are
  /// unique, so no live flag can take the name of one being deleted.
  static Future<int> liveBackgroundRuns(String dbPath) async {
    final dir = Directory(p.dirname(dbPath));
    if (!await dir.exists()) return 0;
    final ours = processToken();
    var live = 0;
    await for (final entity in dir.list()) {
      if (!p.basename(entity.path).startsWith('$kRestoreLockName.bg.')) {
        continue;
      }
      final token = _readToken(entity.path);
      if (token == null) {
        // Lowered while we listed it, or there but unreadable: only the first is gone.
        if (_isPresent(entity.path)) live++;
        continue;
      }
      if (isOwnToken(token, ours)) {
        live++;
      } else {
        _deleteQuietly(entity.path);
      }
    }
    return live;
  }

  /// Deletes the holder file and the flags of processes that no longer live. The recovery
  /// of the app runs it while it holds the lock, so what remains beside the database is
  /// this process's own.
  static Future<void> removeForeignMarks(String dbPath) async {
    final dir = Directory(p.dirname(dbPath));
    if (!await dir.exists()) return;
    final ours = processToken();
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      final isMark =
          name == '$kRestoreLockName.held' ||
          name.startsWith('$kRestoreLockName.bg.');
      if (!isMark) continue;
      final token = _readToken(entity.path);
      if (token != null && !isOwnToken(token, ours)) {
        _deleteQuietly(entity.path);
      }
    }
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
    final held = _heldPath;
    if (held != null) _deleteQuietly(held);
    try {
      await _file.unlock();
    } on FileSystemException {
      // closing releases it anyway
    }
    await _file.close();
    _closeGuard(_guard);
  }
}

/// A background run that may have the database open leaves a flag beside the lock: a
/// file with this process's token. It is raised before the run looks at the lock and
/// lowered only once the database is closed. A restore waits for the flags of its own
/// process ([RestoreLock.liveBackgroundRuns]), whatever their date.
class BackgroundRunFlag {
  BackgroundRunFlag._(this.path);

  final String path;

  /// Raises a flag of its own in the folder of [dbPath]. Throws when it cannot be
  /// written: the run must not go on without it.
  static BackgroundRunFlag raise(String dbPath) {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random().nextInt(1 << 32)}';
    final flag = BackgroundRunFlag._(
      p.join(p.dirname(dbPath), '$kRestoreLockName.bg.$id'),
    );
    _writeToken(flag.path);
    return flag;
  }

  /// Deletes the flag. If it cannot be deleted it stays until this process ends, and the
  /// restores wait for it until then.
  void lower() => _deleteQuietly(path);
}
