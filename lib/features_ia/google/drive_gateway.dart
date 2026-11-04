// Drive access used by the backup service. Own interface so tests can fake Drive (T002).
import 'dart:typed_data';

class DriveBackupFile {
  const DriveBackupFile({
    required this.id,
    required this.name,
    required this.created,
  });

  final String id;
  final String name;
  final DateTime created;
}

/// Operations on the hidden app folder (`appDataFolder`) of the user's Drive.
abstract class DriveGateway {
  /// Backups in the app folder, in any order.
  Future<List<DriveBackupFile>> list();

  Future<DriveBackupFile> upload(String name, Uint8List bytes);

  Future<Uint8List> download(String id);

  Future<void> delete(String id);
}

/// Google account used to reach Drive.
abstract class GoogleAccountGateway {
  /// Email of the account connected without showing any UI, or null.
  Future<String?> silentEmail();

  /// Shows the sign-in and consent UI. Returns the email, or null when cancelled.
  Future<String?> signIn();

  Future<void> signOut();

  /// Drive client for the connected account. [interactive] allows showing the consent UI.
  /// Returns null when there is no session.
  Future<DriveGateway?> openDrive({required bool interactive});
}
