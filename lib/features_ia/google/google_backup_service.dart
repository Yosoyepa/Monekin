// Contract of the Google sign-in and Drive backup (T002). Owner: w-google.
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/backup_database_service.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_key_store.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_password.dart';
import 'package:monekin/features_ia/google/backup_restorer.dart';
import 'package:monekin/features_ia/google/backup_state_store.dart';
import 'package:monekin/features_ia/google/drive_gateway.dart';
import 'package:monekin/features_ia/google/google_account_gateway.dart';
import 'package:path_provider/path_provider.dart';

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

/// There is no Google session (or its Drive permission is missing).
class NotSignedInException implements Exception {
  const NotSignedInException();

  @override
  String toString() => 'NotSignedInException: no Google session';
}

/// There is no backup password yet: copies are never sent unencrypted.
class BackupPasswordRequiredException implements Exception {
  const BackupPasswordRequiredException();

  @override
  String toString() => 'BackupPasswordRequiredException: no backup password';
}

/// A password is already kept on this phone: changing it needs the current one
/// ([DriveBackupService.changePassword]), and forgetting it clears it first.
class BackupPasswordExistsException implements Exception {
  const BackupPasswordExistsException();

  @override
  String toString() => 'BackupPasswordExistsException: a password is kept';
}

/// The current password given to change it is not the one that is kept.
class WrongCurrentPasswordException implements Exception {
  const WrongCurrentPasswordException();

  @override
  String toString() => 'WrongCurrentPasswordException';
}

typedef DatabaseReader = Future<Uint8List> Function();

/// Receives the downloaded copy as it is (v1 database, v2 package or v3 encrypted)
/// and, for a v3, the way to get its key.
typedef DatabaseRestorer =
    Future<void> Function(Uint8List bytes, BackupKeyResolver? resolveKey);

class DriveBackupService implements GoogleBackupService {
  DriveBackupService({
    required this.account,
    required this.state,
    BackupKeyStore? keyStore,
    DatabaseReader? readDatabase,
    DatabaseRestorer? restoreDatabase,
    Future<String> Function()? documentsDir,
    int Function()? schemaVersion,
    DateTime Function()? now,
  }) : keyStore = keyStore ?? SecureBackupKeyStore(),
       _readDatabase =
           readDatabase ?? (() => BackupDatabaseService().getDbFileInBytes()),
       _restoreDatabase = restoreDatabase ?? restoreInApp,
       _documentsDir =
           documentsDir ??
           (() async => (await getApplicationDocumentsDirectory()).path),
       _schemaVersion = schemaVersion ?? (() => AppDB.instance.schemaVersion),
       _now = now ?? DateTime.now;

  /// Service used by the app; `createGoogleBackupService()` returns it.
  static final DriveBackupService shared = DriveBackupService(
    account: RealGoogleAccountGateway(),
    state: FileBackupStateStore(),
  );

  /// Number of copies kept in Drive.
  static const retention = 5;

  static const _prefix = 'finanzas-';

  final GoogleAccountGateway account;
  final BackupStateStore state;
  final BackupKeyStore keyStore;
  final DatabaseReader _readDatabase;
  final DatabaseRestorer _restoreDatabase;
  final Future<String> Function() _documentsDir;
  final int Function() _schemaVersion;
  final DateTime Function() _now;

  /// Encrypted copies end in `.fia`; the v1 and v2 copies of earlier versions are
  /// `.zip` and are not encrypted.
  static const _encryptedExtension = '.fia';

  static String backupName(DateTime date) =>
      '$_prefix${DateFormat('yyyyMMdd-HHmmss').format(date)}$_encryptedExtension';

  Future<bool> hasPassword() async => await keyStore.load() != null;

  /// Derives the master key of [password] and keeps it (never the password). New
  /// copies are sealed with it. There must be no password kept yet: to replace one use
  /// [changePassword], or [forgetPassword] first.
  Future<void> setPassword(String password) async {
    if (!isValidBackupPassword(password)) {
      throw ArgumentError('the password is too short');
    }
    if (await keyStore.load() != null) {
      throw const BackupPasswordExistsException();
    }
    await keyStore.save(await createBackupKey(password));
  }

  /// Whether [password] is the one whose key is kept on this phone.
  Future<bool> verifyPassword(String password) async {
    final stored = await keyStore.load();
    if (stored == null) return false;
    final derived = await deriveKeyBytes(password, stored.salt, stored.params);
    return _sameBytes(derived, stored.key);
  }

  /// Replaces the kept password with [next] after proving the current one. Copies
  /// already made keep the password they were made with.
  Future<void> changePassword(String current, String next) async {
    if (!isValidBackupPassword(next)) {
      throw ArgumentError('the password is too short');
    }
    if (!await verifyPassword(current)) {
      throw const WrongCurrentPasswordException();
    }
    await keyStore.save(await createBackupKey(next));
  }

  /// Removes the key kept on this phone. The copies stay in Drive and still open with
  /// their password; new ones need a new password first.
  Future<void> forgetPassword() => keyStore.clear();

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<String?> signedInEmail() => account.silentEmail();

  Future<String?> signIn() => account.signIn();

  /// Turns the daily copy off and revokes the app's access to the account. If the
  /// revoke fails (no network), the session still ends here and the error is rethrown.
  Future<void> signOut() async {
    await state.setAutoEnabled(false);
    try {
      await account.disconnect();
    } catch (_) {
      await account.signOut();
      rethrow;
    }
  }

  /// Deletes every file of the app folder in Drive. Returns how many were deleted.
  Future<int> deleteAllBackups({bool interactive = true}) async {
    final drive = await _openDrive(interactive);
    final files = await drive.list();
    for (final file in files) {
      await drive.delete(file.id);
    }
    await state.clearLastBackup();
    return files.length;
  }

  /// Deletes only the v1 and v2 copies of the app folder, which are not encrypted.
  /// A copy is only deleted after its bytes are seen not to start like an encrypted
  /// one, whatever its name. Returns how many were deleted.
  Future<int> deleteUnencryptedBackups({bool interactive = true}) async {
    final drive = await _openDrive(interactive);
    var deleted = 0;
    for (final file in _sorted(await drive.list())) {
      if (file.name.endsWith(_encryptedExtension)) continue;
      if (isEncryptedBackup(await drive.download(file.id))) continue;
      await drive.delete(file.id);
      deleted++;
    }
    return deleted;
  }

  /// Whether the app folder holds a v1 or v2 copy by name.
  Future<bool> hasUnencryptedBackups({bool interactive = true}) async {
    final files = await listBackups(interactive: interactive);
    return files.any((f) => !f.name.endsWith(_encryptedExtension));
  }

  Future<bool> autoEnabled() => state.autoEnabled();

  Future<void> setAutoEnabled(bool value) => state.setAutoEnabled(value);

  @override
  Future<bool> isSignedIn() async => await account.silentEmail() != null;

  @override
  Future<DateTime?> lastBackup() => state.lastBackup();

  /// [interactive] allows showing the Drive consent screen; background runs pass false.
  @override
  Future<void> backupNow({bool interactive = true}) async {
    final key = await keyStore.load();
    if (key == null) throw const BackupPasswordRequiredException();

    final drive = await _openDrive(interactive);
    final date = _now();
    final zip = await buildBackupPackage(
      database: await _readDatabase(),
      documentsDir: await _documentsDir(),
      schemaVersion: _schemaVersion(),
      date: date,
    );
    await drive.upload(backupName(date), await encryptBackupBytes(zip, key));
    await state.setLastBackup(date);
    await _prune(drive);
  }

  /// Copies in Drive, newest first.
  Future<List<DriveBackupFile>> listBackups({bool interactive = true}) async {
    final drive = await _openDrive(interactive);
    return _sorted(await drive.list());
  }

  /// The copy as stored in Drive (encrypted, or an older plain one).
  Future<Uint8List> download(
    DriveBackupFile file, {
    bool interactive = true,
  }) async => (await _openDrive(interactive)).download(file.id);

  /// Restores a copy already downloaded. A v3 copy is opened with [password], or with
  /// the stored key when the copy was sealed with it. A v1 or v2 copy is not
  /// encrypted and is refused unless [unencryptedConfirmed]. Throws
  /// [InvalidBackupException] (`passwordRequired`, `wrongPassword`, `tampered`,
  /// `unencrypted`...) before touching anything.
  Future<void> restoreBytes(
    Uint8List bytes, {
    String? password,
    bool unencryptedConfirmed = false,
  }) async {
    BackupKeyResolver? resolver;
    if (isEncryptedBackup(bytes)) {
      final stored = await keyStore.load();
      resolver = password != null
          ? resolverFromPassword(password)
          : stored != null
          ? resolverFromKey(stored)
          : null;
    } else if (!unencryptedConfirmed) {
      throw const InvalidBackupException(
        InvalidBackupReason.unencrypted,
        'the copy is not encrypted',
      );
    }
    await _restoreDatabase(bytes, resolver);
  }

  Future<void> restore(
    DriveBackupFile file, {
    bool interactive = true,
    String? password,
    bool unencryptedConfirmed = false,
  }) async => restoreBytes(
    await download(file, interactive: interactive),
    password: password,
    unencryptedConfirmed: unencryptedConfirmed,
  );

  /// Restores the newest copy. Returns false when Drive holds none.
  Future<bool> restoreLatest({
    bool interactive = true,
    String? password,
    bool unencryptedConfirmed = false,
  }) async {
    final files = await listBackups(interactive: interactive);
    if (files.isEmpty) return false;
    await restore(
      files.first,
      interactive: interactive,
      password: password,
      unencryptedConfirmed: unencryptedConfirmed,
    );
    return true;
  }

  Future<DriveGateway> _openDrive(bool interactive) async {
    final drive = await account.openDrive(interactive: interactive);
    if (drive == null) throw const NotSignedInException();
    return drive;
  }

  List<DriveBackupFile> _sorted(List<DriveBackupFile> files) =>
      files.where((f) => f.name.startsWith(_prefix)).toList()..sort((a, b) {
        final byDate = b.created.compareTo(a.created);
        return byDate != 0 ? byDate : b.name.compareTo(a.name);
      });

  Future<void> _prune(DriveGateway drive) async {
    final files = _sorted(await drive.list());
    for (final old in files.skip(retention)) {
      await drive.delete(old.id);
    }
  }
}
