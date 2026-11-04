import 'dart:io';

import 'package:path/path.dart' as p;

/// Copy kept beside the database before a restore (see `BackupRestorer`).
const kPreRestoreCopyKind = 'pre_restore_backup';

/// Copy kept beside the database before an import (see `BackupDatabaseService`).
const kPreImportCopyKind = 'pre_import_backup';

/// Path of the copy of [kind] that goes with the database at [dbPath].
String preCopyPath(String dbPath, String kind) =>
    p.join(p.dirname(dbPath), '${p.basenameWithoutExtension(dbPath)}.$kind.db');

/// Deletes the copies kept before a restore or an import. [probe] runs first and
/// must query the database: the copies only go once it opens. If [probe] throws,
/// nothing is deleted and the error propagates.
Future<void> deletePreCopiesIfOpens({
  required String dbPath,
  required Future<void> Function() probe,
}) async {
  await probe();

  for (final kind in const [kPreRestoreCopyKind, kPreImportCopyKind]) {
    final copy = File(preCopyPath(dbPath, kind));
    if (await copy.exists()) await copy.delete();
  }
}
