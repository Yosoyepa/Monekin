// Contract of the Google sign-in and Drive backup (T002). Owner: w-google.
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:monekin/core/database/backup/backup_database_service.dart';
import 'package:monekin/features_ia/google/backup_state_store.dart';
import 'package:monekin/features_ia/google/drive_gateway.dart';
import 'package:monekin/features_ia/google/google_account_gateway.dart';

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

typedef DatabaseReader = Future<Uint8List> Function();
typedef DatabaseRestorer = Future<void> Function(Uint8List bytes);

class DriveBackupService implements GoogleBackupService {
  DriveBackupService({
    required this.account,
    required this.state,
    DatabaseReader? readDatabase,
    DatabaseRestorer? restoreDatabase,
    DateTime Function()? now,
  }) : _readDatabase =
           readDatabase ?? (() => BackupDatabaseService().getDbFileInBytes()),
       _restoreDatabase =
           restoreDatabase ?? BackupDatabaseService().importDatabaseFromBytes,
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
  final DatabaseReader _readDatabase;
  final DatabaseRestorer _restoreDatabase;
  final DateTime Function() _now;

  static String backupName(DateTime date) =>
      '$_prefix${DateFormat('yyyyMMdd-HHmmss').format(date)}.db';

  Future<String?> signedInEmail() => account.silentEmail();

  Future<String?> signIn() => account.signIn();

  Future<void> signOut() async {
    await account.signOut();
    await state.setAutoEnabled(false);
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
    final drive = await _openDrive(interactive);
    final bytes = await _readDatabase();
    final date = _now();
    await drive.upload(backupName(date), bytes);
    await state.setLastBackup(date);
    await _prune(drive);
  }

  /// Copies in Drive, newest first.
  Future<List<DriveBackupFile>> listBackups({bool interactive = true}) async {
    final drive = await _openDrive(interactive);
    return _sorted(await drive.list());
  }

  Future<void> restore(DriveBackupFile file, {bool interactive = true}) async {
    final drive = await _openDrive(interactive);
    await _restoreDatabase(await drive.download(file.id));
  }

  /// Restores the newest copy. Returns false when Drive holds none.
  Future<bool> restoreLatest({bool interactive = true}) async {
    final files = await listBackups(interactive: interactive);
    if (files.isEmpty) return false;
    await restore(files.first, interactive: interactive);
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
