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

  static String backupName(DateTime date) =>
      '$_prefix${DateFormat('yyyyMMdd-HHmmss').format(date)}.zip';

  Future<bool> hasPassword() async => await keyStore.load() != null;

  /// Derives the key of [password] and keeps it (never the password). New copies are
  /// sealed with it; older ones still ask for the password they were made with.
  Future<void> setPassword(String password) async {
    if (!isValidBackupPassword(password)) {
      throw ArgumentError('the password is too short');
    }
    await keyStore.save(await createBackupKey(password));
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
  /// the stored key when the copy was sealed with it. Throws [InvalidBackupException]
  /// (`passwordRequired`, `wrongPassword`, `tampered`...) before touching anything.
  Future<void> restoreBytes(Uint8List bytes, {String? password}) async {
    BackupKeyResolver? resolver;
    if (isEncryptedBackup(bytes)) {
      final stored = await keyStore.load();
      resolver = password != null
          ? resolverFromPassword(password)
          : stored != null
          ? resolverFromKey(stored)
          : null;
    }
    await _restoreDatabase(bytes, resolver);
  }

  Future<void> restore(
    DriveBackupFile file, {
    bool interactive = true,
    String? password,
  }) async => restoreBytes(
    await download(file, interactive: interactive),
    password: password,
  );

  /// Restores the newest copy. Returns false when Drive holds none.
  Future<bool> restoreLatest({
    bool interactive = true,
    String? password,
  }) async {
    final files = await listBackups(interactive: interactive);
    if (files.isEmpty) return false;
    await restore(files.first, interactive: interactive, password: password);
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
