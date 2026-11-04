import 'dart:convert';
import 'dart:io';

import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/core/database/services/user-setting/user_setting_service.dart';
import 'package:monekin/core/utils/logger.dart';
import 'package:path_provider/path_provider.dart';

/// Value the old default stored for "use the device colors".
const _dynamicColorsValue = 'auto';

/// Name of the file in the documents folder that remembers the migration ran.
const brandMigrationFileName = 'brand_migration.json';

/// Moves installs that still hold the old factory default (`auto`, dynamic
/// colors) to the brand accent, once. The marker is written on the first run
/// whatever the accent was, so a user who later turns dynamic colors back on
/// keeps them.
///
/// Returns `true` when the accent was changed.
Future<bool> migrateToBrandAccent({
  required String? currentAccent,
  required Future<void> Function(String accentHex) saveAccent,
  required File marker,
}) async {
  if (await marker.exists()) return false;

  final shouldMigrate = currentAccent == _dynamicColorsValue;
  if (shouldMigrate) await saveAccent(BrandTokens.accentHex);

  await marker.writeAsString(jsonEncode({'done': true}));

  return shouldMigrate;
}

/// Runs [migrateToBrandAccent] against the stored settings. Call it before
/// `runApp`, so the first frame already uses the brand accent.
Future<void> runBrandMigration() async {
  try {
    final documents = await getApplicationDocumentsDirectory();

    await migrateToBrandAccent(
      currentAccent: appStateSettings[SettingKey.accentColor],
      saveAccent: (hex) =>
          UserSettingService.instance.setItem(SettingKey.accentColor, hex),
      marker: File('${documents.path}/$brandMigrationFileName'),
    );
  } catch (e) {
    Logger.printDebug('Brand migration skipped: $e');
  }
}
