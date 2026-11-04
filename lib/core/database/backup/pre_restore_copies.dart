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

/// Path of the copy of [kind] that goes with the database at [dbPath].
String preCopyPath(String dbPath, String kind) =>
    p.join(p.dirname(dbPath), '${p.basenameWithoutExtension(dbPath)}.$kind.db');

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
      File(preCopyPath(dbPath, kind)),
  ].where((copy) => copy.existsSync()).toList();

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
