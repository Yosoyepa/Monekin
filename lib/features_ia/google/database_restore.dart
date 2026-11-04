// Restores the app database from backup bytes (T002).
// Same procedure as BackupDatabaseService.importDatabase (upstream), which only accepts a file picked by the user.
import 'dart:io';
import 'dart:typed_data';

import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/app-data/app_data_service.dart';
import 'package:monekin/core/database/services/taxonomy/taxonomy_service.dart';
import 'package:monekin/core/utils/logger.dart';
import 'package:path/path.dart' as path;

Future<void> restoreDatabaseFromBytes(Uint8List bytes) async {
  final db = AppDB.instance;
  final dbPath = await db.databasePath;
  final currentDBContent = await File(dbPath).readAsBytes();

  await File(dbPath).writeAsBytes(bytes, mode: FileMode.write);

  try {
    final dbVersion = int.parse(
      (await AppDataService.instance
          .getAppDataItem(AppDataKey.dbVersion)
          .first)!,
    );

    if (dbVersion < db.schemaVersion) {
      await db.migrateDB(dbVersion, db.schemaVersion);
    }

    await TaxonomyService.instance.ensureSeeded();

    db.markTablesUpdated(db.allTables);
  } catch (e) {
    Logger.printDebug('Error\n: $e');

    if (e is MigrationFailedException) {
      final previousDbBackupPath = path.join(
        path.dirname(dbPath),
        '${path.basenameWithoutExtension(dbPath)}.pre_import_backup.db',
      );

      await File(
        previousDbBackupPath,
      ).writeAsBytes(currentDBContent, mode: FileMode.write);

      db.markTablesUpdated(db.allTables);
      rethrow;
    }

    await File(dbPath).writeAsBytes(currentDBContent, mode: FileMode.write);
    db.markTablesUpdated(db.allTables);

    throw Exception('The database is invalid or could not be readed');
  }
}
