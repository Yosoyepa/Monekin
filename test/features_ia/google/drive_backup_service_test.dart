import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_state_store.dart';
import 'package:monekin/features_ia/google/drive_gateway.dart';
import 'package:monekin/features_ia/google/google_background.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';
import 'package:path/path.dart' as p;

class FakeDrive implements DriveGateway {
  final files = <String, Uint8List>{};
  final meta = <String, DriveBackupFile>{};
  int _next = 0;
  DateTime Function() clock = DateTime.now;

  @override
  Future<List<DriveBackupFile>> list() async => meta.values.toList();

  @override
  Future<DriveBackupFile> upload(String name, Uint8List bytes) async {
    final id = 'id${_next++}';
    final file = DriveBackupFile(id: id, name: name, created: clock());
    files[id] = bytes;
    meta[id] = file;
    return file;
  }

  @override
  Future<Uint8List> download(String id) async => files[id]!;

  /// Files of the user's Drive outside the app folder; the gateway never lists them.
  final outsideAppFolder = <String, Uint8List>{
    'user-photo': Uint8List.fromList([4, 2]),
  };
  final deletedIds = <String>[];

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    files.remove(id);
    meta.remove(id);
  }
}

class FakeAccount implements GoogleAccountGateway {
  FakeAccount({this.email, this.drive});

  String? email;
  FakeDrive? drive;
  bool? lastInteractive;

  @override
  Future<String?> silentEmail() async => email;

  @override
  Future<String?> signIn() async => email;

  @override
  Future<void> signOut() async {
    email = null;
    signedOut = true;
  }

  bool disconnected = false;
  bool signedOut = false;
  Object? disconnectError;

  @override
  Future<void> disconnect() async {
    if (disconnectError != null) throw disconnectError!;
    disconnected = true;
    email = null;
  }

  @override
  Future<DriveGateway?> openDrive({required bool interactive}) async {
    lastInteractive = interactive;
    return email == null ? null : drive;
  }
}

void main() {
  late FakeDrive drive;
  late FakeAccount account;
  late MemoryBackupStateStore state;
  late DateTime now;
  late List<Uint8List> restored;
  late DriveBackupService service;
  late Directory docs;

  DriveBackupService serviceWith({DatabaseReader? read}) => DriveBackupService(
    account: account,
    state: state,
    readDatabase: read ?? () async => Uint8List.fromList([1, 2, 3]),
    restoreDatabase: (bytes) async => restored.add(bytes),
    documentsDir: () async => docs.path,
    schemaVersion: () => 15,
    now: () => now,
  );

  setUp(() {
    docs = Directory.systemTemp.createTempSync('drive_backup_test');
    now = DateTime(2026, 11, 4, 8, 30, 5);
    drive = FakeDrive()..clock = () => now;
    account = FakeAccount(email: 'a@b.com', drive: drive);
    state = MemoryBackupStateStore();
    restored = [];
    service = serviceWith();
  });

  tearDown(() => docs.deleteSync(recursive: true));

  test('backupName uses a sortable timestamp', () {
    expect(
      DriveBackupService.backupName(DateTime(2026, 1, 2, 3, 4, 5)),
      'finanzas-20260102-030405.zip',
    );
  });

  test(
    'backupNow uploads the database with that name and stores the date',
    () async {
      await service.backupNow();

      expect(drive.meta.values.single.name, 'finanzas-20261104-083005.zip');
      final package = parseBackupPackage(drive.files.values.single);
      expect(package.database, [1, 2, 3]);
      expect(package.schemaVersion, 15);
      expect(await service.lastBackup(), now);
    },
  );

  test('backupNow packs the receipt photos', () async {
    final receipts = Directory(receiptsDirOf(docs.path))
      ..createSync(recursive: true);
    File(p.join(receipts.path, 'a.jpg')).writeAsBytesSync([9, 9]);
    File(p.join(receipts.path, 'b.jpg')).writeAsBytesSync([8]);

    await service.backupNow();

    final package = parseBackupPackage(drive.files.values.single);
    expect(package.photos.keys.toSet(), {'a.jpg', 'b.jpg'});
    expect(package.photos['a.jpg'], [9, 9]);
    expect(package.sourceDocumentsDir, docs.path);
  });

  test('keeps only the 5 newest copies', () async {
    for (var i = 0; i < 7; i++) {
      now = DateTime(2026, 11, 1 + i, 8);
      await service.backupNow();
    }

    final names = (await service.listBackups()).map((f) => f.name).toList();
    expect(names, hasLength(5));
    expect(names.first, 'finanzas-20261107-080000.zip');
    expect(names.last, 'finanzas-20261103-080000.zip');
  });

  test('retention ignores files that are not Finanzas copies', () async {
    await drive.upload('other.txt', Uint8List(1));
    for (var i = 0; i < 6; i++) {
      now = DateTime(2026, 11, 1 + i, 8);
      await service.backupNow();
    }

    expect(drive.meta.values.where((f) => f.name == 'other.txt'), hasLength(1));
    expect(
      drive.meta.values.where((f) => f.name.startsWith('finanzas-')),
      hasLength(5),
    );
  });

  test('restoreLatest restores the newest copy', () async {
    for (var i = 0; i < 3; i++) {
      now = DateTime(2026, 11, 1 + i, 8);
      final bytes = Uint8List.fromList([i]);
      service = serviceWith(read: () async => bytes);
      await service.backupNow();
    }

    expect(await service.restoreLatest(), isTrue);
    expect(parseBackupPackage(restored.single).database, [2]);
  });

  test('restoreLatest returns false when Drive has no copies', () async {
    expect(await service.restoreLatest(), isFalse);
    expect(restored, isEmpty);
  });

  test('backupNow without a session throws NotSignedInException', () async {
    account.email = null;
    expect(service.backupNow(), throwsA(isA<NotSignedInException>()));
  });

  test('signOut turns the daily copy off and revokes the access', () async {
    await service.setAutoEnabled(true);
    await service.signOut();
    expect(await service.autoEnabled(), isFalse);
    expect(await service.isSignedIn(), isFalse);
    expect(account.disconnected, isTrue);
  });

  test('signOut still ends the session if the revoke fails', () async {
    account.disconnectError = Exception('offline');

    await expectLater(service.signOut(), throwsException);

    expect(account.signedOut, isTrue);
    expect(await service.isSignedIn(), isFalse);
  });

  group('deleteAllBackups', () {
    test('deletes the files of the app folder and nothing else', () async {
      for (var i = 0; i < 3; i++) {
        now = DateTime(2026, 11, 1 + i, 8);
        await service.backupNow();
      }
      await drive.upload('other.txt', Uint8List(1));
      final listed = drive.meta.keys.toSet();

      final deleted = await service.deleteAllBackups();

      expect(deleted, 4);
      expect(drive.meta, isEmpty);
      expect(drive.deletedIds.toSet(), listed);
      expect(drive.outsideAppFolder.keys, ['user-photo']);
      expect(await service.lastBackup(), isNull);
    });

    test('with no copies it deletes nothing', () async {
      expect(await service.deleteAllBackups(), 0);
      expect(drive.deletedIds, isEmpty);
    });

    test('without a session it throws NotSignedInException', () async {
      account.email = null;

      await expectLater(
        service.deleteAllBackups(),
        throwsA(isA<NotSignedInException>()),
      );
      expect(drive.deletedIds, isEmpty);
    });
  });

  group('runDriveBackupTask', () {
    test('without a session finishes with true and uploads nothing', () async {
      account.email = null;
      expect(await runDriveBackupTask(service: service), isTrue);
      expect(drive.meta, isEmpty);
    });

    test('session without Drive permission finishes with true', () async {
      account.drive = null;
      expect(await runDriveBackupTask(service: service), isTrue);
    });

    test('with a session backs up silently', () async {
      expect(await runDriveBackupTask(service: service), isTrue);
      expect(drive.meta, hasLength(1));
      expect(account.lastInteractive, isFalse);
    });

    test('a Drive failure returns false so workmanager retries', () async {
      service = serviceWith(read: () async => throw Exception('disk'));
      expect(await runDriveBackupTask(service: service), isFalse);
    });
  });
}
