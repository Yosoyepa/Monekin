// Contract of the Google sign-in and Drive backup (T002). Owner: w-google.
abstract class GoogleBackupService {
  /// Replaced at startup by `initFeaturesIa()`.
  static GoogleBackupService instance = NotReadyGoogleBackupService();

  Future<bool> isSignedIn();

  /// Uploads the current database backup to the app folder of the user's Drive.
  Future<void> backupNow();

  Future<DateTime?> lastBackup();
}

class NotReadyGoogleBackupService implements GoogleBackupService {
  @override
  Future<bool> isSignedIn() async => false;

  @override
  Future<void> backupNow() async {}

  @override
  Future<DateTime?> lastBackup() async => null;
}
