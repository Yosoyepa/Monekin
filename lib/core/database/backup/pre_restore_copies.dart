import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copy kept beside the database before a restore (see `BackupRestorer`).
const kPreRestoreCopyKind = 'pre_restore_backup';

/// Copy kept beside the database before an import (see `BackupDatabaseService`).
const kPreImportCopyKind = 'pre_import_backup';

/// The copies only go after this long, or after [kPreCopiesMinBoots] good starts,
/// whichever comes first.
const kPreCopiesMinAge = Duration(days: 7);
const kPreCopiesMinBoots = 3;

/// How many copies of each kind are kept: the two latest.
const kPreCopiesKept = 2;

/// Path of the undated copy of [kind] that goes with the database at [dbPath]; the
/// only form earlier versions wrote, still found and cleaned.
String preCopyPath(String dbPath, String kind) =>
    p.join(p.dirname(dbPath), '${p.basenameWithoutExtension(dbPath)}.$kind.db');

String _two(int n) => n.toString().padLeft(2, '0');

String _stampOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}-'
    '${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

/// Path for a new copy of [kind], named after [now]; moves on a second at a time if
/// that name is taken, so a copy never overwrites an earlier one.
String newPreCopyPath(String dbPath, String kind, DateTime now) {
  final dir = p.dirname(dbPath);
  final base = p.basenameWithoutExtension(dbPath);
  var moment = now;
  while (true) {
    final path = p.join(dir, '$base.$kind.${_stampOf(moment)}.db');
    if (!File(path).existsSync()) return path;
    moment = moment.add(const Duration(seconds: 1));
  }
}

/// The copies of [kind] beside [dbPath], oldest first: the undated one of earlier
/// versions and then the dated ones.
List<File> preCopyFiles(String dbPath, String kind) {
  final dir = Directory(p.dirname(dbPath));
  if (!dir.existsSync()) return [];
  final prefix = '${p.basenameWithoutExtension(dbPath)}.$kind';
  final dated = RegExp('^${RegExp.escape(prefix)}\\.\\d{8}-\\d{6}\\.db\$');
  final found = <File>[
    for (final entity in dir.listSync())
      if (entity is File &&
          (p.basename(entity.path) == '$prefix.db' ||
              dated.hasMatch(p.basename(entity.path))))
        entity,
  ];
  int rank(File f) => p.basename(f.path) == '$prefix.db' ? 0 : 1;
  return found..sort((a, b) {
    final byAge = rank(a).compareTo(rank(b));
    return byAge != 0 ? byAge : a.path.compareTo(b.path);
  });
}

/// Deletes the oldest copies of [kind], keeping the latest [keep].
Future<void> prunePreCopies(
  String dbPath,
  String kind, {
  int keep = kPreCopiesKept,
}) async {
  final copies = preCopyFiles(dbPath, kind);
  if (copies.length <= keep) return;
  for (final old in copies.take(copies.length - keep)) {
    await old.delete();
  }
}

/// Runs one read-only SQL statement on the live database.
typedef SqlQuery = Future<List<Map<String, Object?>>> Function(String sql);

/// Throws unless the database passes `integrity_check`, has the expected
/// `user_version` and every table in [requiredTables], and answers a real query on
/// accounts and transactions. The message never carries data from the database.
Future<void> checkDatabaseHealth(
  SqlQuery query, {
  required int userVersion,
  required Iterable<String> requiredTables,
}) async {
  final integrity = await query('PRAGMA integrity_check');
  if (integrity.length != 1 || integrity.first.values.first != 'ok') {
    throw StateError('integrity_check failed');
  }

  final version = (await query('PRAGMA user_version')).first.values.first;
  if (version != userVersion) throw StateError('unexpected user_version');

  final tables = {
    for (final row in await query(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ))
      row['name'],
  };
  if (!tables.containsAll(requiredTables)) throw StateError('missing tables');

  await query('SELECT COUNT(*) FROM accounts');
  await query('SELECT COUNT(*) FROM transactions');
}

/// What the app remembers about the copies kept before a restore or an import:
/// since when, how many good starts since, and whether a check failed. Kept in its
/// own file, so it survives the database being replaced.
class PreCopiesState {
  PreCopiesState(this._file);

  /// The file in the app support folder.
  factory PreCopiesState.inSupportDir() => PreCopiesState(
    () async => File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'finanzas_pre_copies.json',
      ),
    ),
  );

  final Future<File> Function() _file;

  Future<Map<String, dynamic>> _read() async {
    final f = await _file();
    if (!f.existsSync()) return {};
    try {
      final decoded = jsonDecode(await f.readAsString());
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final f = await _file();
    await f.create(recursive: true);
    await f.writeAsString(jsonEncode(data), flush: true);
  }

  /// A new copy was just kept: the waiting starts again.
  Future<void> markCopyKept(DateTime now) => _write({
    'restoredAt': now.toIso8601String(),
    'boots': 0,
    'warning': false,
  });

  /// Whether the last check failed and the copies are still there.
  Future<bool> hasWarning() async => (await _read())['warning'] == true;

  Future<void> clear() async {
    final f = await _file();
    if (f.existsSync()) await f.delete();
  }
}

enum PreCopiesOutcome { noCopies, kept, deleted, failedCheck }

/// Deletes the copies kept before a restore or an import, only once the database
/// is proven healthy by [check] and the copies have waited [kPreCopiesMinAge] or
/// [kPreCopiesMinBoots] good starts. If [check] throws the copies stay and
/// [PreCopiesState.hasWarning] turns on until a later check passes.
Future<PreCopiesOutcome> cleanPreCopies({
  required String dbPath,
  required PreCopiesState state,
  required Future<void> Function() check,
  required DateTime now,
}) async {
  final copies = [
    for (final kind in const [kPreRestoreCopyKind, kPreImportCopyKind])
      ...preCopyFiles(dbPath, kind),
  ];

  if (copies.isEmpty) {
    await state.clear();
    return PreCopiesOutcome.noCopies;
  }

  final data = await state._read();
  final restoredAt = DateTime.tryParse('${data['restoredAt']}') ?? now;

  try {
    await check();
  } catch (_) {
    await state._write({
      'restoredAt': restoredAt.toIso8601String(),
      'boots': data['boots'] is int ? data['boots'] : 0,
      'warning': true,
    });
    return PreCopiesOutcome.failedCheck;
  }

  final boots = (data['boots'] is int ? data['boots'] as int : 0) + 1;
  if (now.difference(restoredAt) >= kPreCopiesMinAge ||
      boots >= kPreCopiesMinBoots) {
    for (final copy in copies) {
      await copy.delete();
    }
    await state.clear();
    return PreCopiesOutcome.deleted;
  }

  await state._write({
    'restoredAt': restoredAt.toIso8601String(),
    'boots': boots,
    'warning': false,
  });
  return PreCopiesOutcome.kept;
}
