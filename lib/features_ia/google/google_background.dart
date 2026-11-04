// Background task handler of the daily Drive backup (T002). Owner: w-google.
import 'package:monekin/core/utils/logger.dart';
import 'package:monekin/features_ia/google/drive_gateway.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';

/// Returns true when it finished or there is nothing to do (no session); false asks workmanager to retry.
Future<bool> runDriveBackupTask({DriveBackupService? service}) async {
  final backup = service ?? DriveBackupService.shared;
  try {
    if (!await backup.isSignedIn()) return true;
    await backup.backupNow(interactive: false);
    return true;
  } on NotSignedInException {
    return true;
  } on GoogleNotConfiguredException {
    return true;
  } on BackupPasswordRequiredException {
    // Nothing is uploaded unencrypted; the user sets the password in the app.
    return true;
  } catch (e) {
    Logger.printDebug('Drive backup task failed: $e');
    return false;
  }
}
