import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_state_store.dart';
import 'package:monekin/features_ia/google/drive_gateway.dart';
import 'package:monekin/features_ia/google/google_background.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';

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

  @override
  Future<void> delete(String id) async {
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
  Future<void> signOut() async => email = null;

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

  setUp(() {
    now = DateTime(2026, 11, 4, 8, 30, 5);
    drive = FakeDrive()..clock = () => now;
    account = FakeAccount(email: 'a@b.com', drive: drive);
    state = MemoryBackupStateStore();
    restored = [];
    service = DriveBackupService(
      account: account,
      state: state,
      readDatabase: () async => Uint8List.fromList([1, 2, 3]),
      restoreDatabase: (bytes) async => restored.add(bytes),
      now: () => now,
    );
  });

  test('backupName uses a sortable timestamp', () {
    expect(
      DriveBackupService.backupName(DateTime(2026, 1, 2, 3, 4, 5)),
      'finanzas-20260102-030405.db',
    );
  });

  test(
    'backupNow uploads the database with that name and stores the date',
    () async {
      await service.backupNow();

      expect(drive.meta.values.single.name, 'finanzas-20261104-083005.db');
      expect(drive.files.values.single, [1, 2, 3]);
      expect(await service.lastBackup(), now);
    },
  );

  test('keeps only the 5 newest copies', () async {
    for (var i = 0; i < 7; i++) {
      now = DateTime(2026, 11, 1 + i, 8);
      await service.backupNow();
    }

    final names = (await service.listBackups()).map((f) => f.name).toList();
    expect(names, hasLength(5));
    expect(names.first, 'finanzas-20261107-080000.db');
    expect(names.last, 'finanzas-20261103-080000.db');
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
      service = DriveBackupService(
        account: account,
        state: state,
        readDatabase: () async => bytes,
        restoreDatabase: (b) async => restored.add(b),
        now: () => now,
      );
      await service.backupNow();
    }

    expect(await service.restoreLatest(), isTrue);
    expect(restored.single, [2]);
  });

  test('restoreLatest returns false when Drive has no copies', () async {
    expect(await service.restoreLatest(), isFalse);
    expect(restored, isEmpty);
  });

  test('backupNow without a session throws NotSignedInException', () async {
    account.email = null;
    expect(service.backupNow(), throwsA(isA<NotSignedInException>()));
  });

  test('signOut turns the daily copy off', () async {
    await service.setAutoEnabled(true);
    await service.signOut();
    expect(await service.autoEnabled(), isFalse);
    expect(await service.isSignedIn(), isFalse);
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
      service = DriveBackupService(
        account: account,
        state: state,
        readDatabase: () async => throw Exception('disk'),
        now: () => now,
      );
      expect(await runDriveBackupTask(service: service), isFalse);
    });
  });
}
