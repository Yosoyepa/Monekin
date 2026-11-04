import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_key_store.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_state_store.dart';
import 'package:monekin/features_ia/google/drive_gateway.dart';
import 'package:monekin/features_ia/google/google_background.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';
import 'package:path/path.dart' as p;

import 'backup_crypto_test.dart' show testParams;

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
  late List<BackupKeyResolver?> resolvers;
  late MemoryBackupKeyStore keys;
  late BackupKey key;
  late DriveBackupService service;
  late Directory docs;

  DriveBackupService serviceWith({DatabaseReader? read}) => DriveBackupService(
    account: account,
    state: state,
    keyStore: keys,
    readDatabase: read ?? () async => Uint8List.fromList([1, 2, 3]),
    restoreDatabase: (bytes, resolver) async {
      restored.add(bytes);
      resolvers.add(resolver);
    },
    documentsDir: () async => docs.path,
    schemaVersion: () => 15,
    now: () => now,
  );

  setUpAll(() async {
    key = await createBackupKey('a long enough password', params: testParams);
  });

  /// What Drive holds, opened with the key of the service.
  Future<BackupPackage> open(Uint8List stored) async => parseBackupPackage(
    await decryptBackupBytes(stored, resolverFromKey(key)),
  );

  setUp(() {
    keys = MemoryBackupKeyStore()..save(key);
    resolvers = [];
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
      'finanzas-20260102-030405.fia',
    );
  });

  test(
    'backupNow uploads the database with that name and stores the date',
    () async {
      await service.backupNow();

      expect(drive.meta.values.single.name, 'finanzas-20261104-083005.fia');
      final package = await open(drive.files.values.single);
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

    final package = await open(drive.files.values.single);
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
    expect(names.first, 'finanzas-20261107-080000.fia');
    expect(names.last, 'finanzas-20261103-080000.fia');
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
    expect((await open(restored.single)).database, [2]);
  });

  test('restoreLatest returns false when Drive has no copies', () async {
    expect(await service.restoreLatest(), isFalse);
    expect(restored, isEmpty);
  });

  group('encryption', () {
    test('what is uploaded is encrypted and holds no readable data', () async {
      service = serviceWith(
        read: () async => Uint8List.fromList(List.filled(64, 0x5a)),
      );
      await service.backupNow();

      final stored = drive.files.values.single;
      expect(isEncryptedBackup(stored), isTrue);
      expect(stored.sublist(0, 4), isNot([0x50, 0x4b, 0x03, 0x04]));
      expect(
        String.fromCharCodes(stored),
        isNot(contains('finanzas-ia-backup')),
      );
    });

    test('without a password nothing is uploaded and it says so', () async {
      await keys.clear();

      await expectLater(
        service.backupNow(),
        throwsA(isA<BackupPasswordRequiredException>()),
      );
      expect(drive.meta, isEmpty);
      expect(await service.lastBackup(), isNull);
    });

    test(
      'the daily task without a password finishes and uploads nothing',
      () async {
        await keys.clear();

        expect(await runDriveBackupTask(service: service), isTrue);
        expect(drive.meta, isEmpty);
      },
    );

    test(
      'setPassword keeps the derived key, and short ones are refused',
      () async {
        await keys.clear();
        expect(await service.hasPassword(), isFalse);

        expect(() => service.setPassword('short'), throwsArgumentError);
        expect(
          () => service.setPassword('eleven char'),
          throwsArgumentError,
          reason: 'under 12 characters and under 4 words',
        );
        expect(await service.hasPassword(), isFalse);

        await service.setPassword('long enough password');
        expect(await service.hasPassword(), isTrue);

        await service.backupNow();
        final stored = drive.files.values.single;
        expect(
          parseBackupPackage(
            await decryptBackupBytes(
              stored,
              resolverFromPassword('long enough password'),
            ),
          ).database,
          [1, 2, 3],
        );
      },
    );

    test(
      'secure storage keeps the derived key and never the password',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        const password = 'my private drive password 2026';
        final real = DriveBackupService(
          account: account,
          state: state,
          keyStore: SecureBackupKeyStore(),
          readDatabase: () async => Uint8List.fromList([1, 2, 3]),
          restoreDatabase: (bytes, resolver) async {},
          documentsDir: () async => docs.path,
          schemaVersion: () => 15,
          now: () => now,
        );

        await real.setPassword(password);
        await real.backupNow();

        final everything = await const FlutterSecureStorage().readAll();
        expect(everything.keys, [SecureBackupKeyStore.storageKey]);
        for (final entry in everything.entries) {
          expect(entry.key, isNot(contains(password)));
          expect(entry.value, isNot(contains(password)));
        }
        expect(
          parseBackupPackage(
            await decryptBackupBytes(
              drive.files.values.single,
              resolverFromPassword(password),
            ),
          ).database,
          [1, 2, 3],
        );
      },
    );

    test(
      'restoring a copy hands it over with a resolver for its key',
      () async {
        await service.backupNow();
        final stored = drive.files.values.single;

        await service.restoreBytes(stored);
        expect(restored.single, stored);
        expect(await decryptBackupBytes(stored, resolvers.single!), isNotEmpty);
      },
    );

    test('an older copy asks for the password it was made with', () async {
      await service.backupNow();
      final stored = drive.files.values.single;

      await service.changePassword(
        'a long enough password',
        'the new password',
      );
      await service.restoreBytes(stored);
      await expectLater(
        decryptBackupBytes(stored, resolvers.single!),
        throwsA(
          isA<InvalidBackupException>().having(
            (e) => e.reason,
            'reason',
            InvalidBackupReason.passwordRequired,
          ),
        ),
      );

      await service.restoreBytes(stored, password: 'a long enough password');
      expect(await decryptBackupBytes(stored, resolvers.last!), isNotEmpty);
    });

    test('a plain v2 copy is handed over without a resolver', () async {
      final plain = await buildBackupPackage(
        database: Uint8List.fromList([1]),
        documentsDir: docs.path,
        schemaVersion: 15,
        date: now,
      );

      await service.restoreBytes(plain, unencryptedConfirmed: true);
      expect(resolvers.single, isNull);
    });

    test('a v1 or v2 copy is refused until the user confirms', () async {
      final v2 = await buildBackupPackage(
        database: Uint8List.fromList([1]),
        documentsDir: docs.path,
        schemaVersion: 15,
        date: now,
      );

      for (final copy in [
        v2,
        Uint8List.fromList([1, 2, 3]),
      ]) {
        await expectLater(
          service.restoreBytes(copy),
          throwsA(
            isA<InvalidBackupException>().having(
              (e) => e.reason,
              'reason',
              InvalidBackupReason.unencrypted,
            ),
          ),
        );
      }
      expect(restored, isEmpty);

      await service.restoreBytes(v2, unencryptedConfirmed: true);
      expect(restored.single, v2);
    });

    test('an encrypted copy needs no confirmation', () async {
      await service.backupNow();

      await service.restoreBytes(drive.files.values.single);

      expect(restored, hasLength(1));
    });
  });

  group('password', () {
    test('setPassword refuses to replace a password that is kept', () async {
      expect(
        () => service.setPassword('another long password'),
        throwsA(isA<BackupPasswordExistsException>()),
      );
      expect(
        await service.verifyPassword('a long enough password'),
        isTrue,
        reason: 'the kept key is untouched',
      );
    });

    test('four words are enough even when short', () async {
      await keys.clear();

      await service.setPassword('sol luna mar rio');

      expect(await service.hasPassword(), isTrue);
    });

    test('changing it asks for the current one', () async {
      await expectLater(
        service.changePassword('not the current one', 'a brand new password'),
        throwsA(isA<WrongCurrentPasswordException>()),
      );
      expect(await service.verifyPassword('a long enough password'), isTrue);
      expect(await service.verifyPassword('a brand new password'), isFalse);

      await service.changePassword(
        'a long enough password',
        'a brand new password',
      );

      expect(await service.verifyPassword('a brand new password'), isTrue);
      expect(await service.verifyPassword('a long enough password'), isFalse);
    });

    test('the new password must be a valid one too', () async {
      await expectLater(
        service.changePassword('a long enough password', 'short'),
        throwsArgumentError,
      );
      expect(await service.verifyPassword('a long enough password'), isTrue);
    });

    test('copies already made keep the password they were made with', () async {
      await service.backupNow();
      final stored = drive.files.values.single;

      await service.changePassword(
        'a long enough password',
        'a brand new password',
      );

      await expectLater(
        decryptBackupBytes(
          stored,
          resolverFromPassword('a brand new password'),
        ),
        throwsA(isA<InvalidBackupException>()),
      );
      expect(
        await decryptBackupBytes(
          stored,
          resolverFromPassword('a long enough password'),
        ),
        isNotEmpty,
      );
    });

    test('forgetting it clears the key kept on the phone', () async {
      await service.backupNow();
      final stored = drive.files.values.single;

      await service.forgetPassword();

      expect(await service.hasPassword(), isFalse);
      expect(await service.verifyPassword('a long enough password'), isFalse);
      await expectLater(
        service.backupNow(),
        throwsA(isA<BackupPasswordRequiredException>()),
      );
      expect(
        drive.meta,
        hasLength(1),
        reason: 'copies in Drive are not touched',
      );
      expect(
        await decryptBackupBytes(
          stored,
          resolverFromPassword('a long enough password'),
        ),
        isNotEmpty,
        reason: 'and still open with their password',
      );
    });

    test('forgetting it leaves nothing in the secure storage', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final real = DriveBackupService(
        account: account,
        state: state,
        keyStore: SecureBackupKeyStore(),
        readDatabase: () async => Uint8List.fromList([1]),
        restoreDatabase: (bytes, resolver) async {},
        documentsDir: () async => docs.path,
        schemaVersion: () => 15,
        now: () => now,
      );
      await real.setPassword('a long enough password');
      expect(await const FlutterSecureStorage().readAll(), isNotEmpty);

      await real.forgetPassword();

      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    });
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

  group('deleteUnencryptedBackups', () {
    late Uint8List v1;
    late Uint8List v2;
    late Uint8List sealedWithZipName;

    setUp(() async {
      v1 = Uint8List.fromList([1, 2, 3]);
      v2 = await buildBackupPackage(
        database: v1,
        documentsDir: docs.path,
        schemaVersion: 15,
        date: now,
      );
      sealedWithZipName = await encryptBackupBytes(v2, key);
    });

    test('deletes only the v1 and v2 copies of the app folder', () async {
      await service.backupNow();
      final encrypted = drive.meta.values.single.id;
      final legacyV1 = await drive.upload('finanzas-20260101-000000.zip', v1);
      final legacyV2 = await drive.upload('finanzas-20260102-000000.zip', v2);
      final disguised = await drive.upload(
        'finanzas-20260103-000000.zip',
        sealedWithZipName,
      );
      final other = await drive.upload('other.txt', Uint8List(1));

      final deleted = await service.deleteUnencryptedBackups();

      expect(deleted, 2);
      expect(drive.deletedIds.toSet(), {legacyV1.id, legacyV2.id});
      expect(drive.meta.keys.toSet(), {encrypted, disguised.id, other.id});
      expect(drive.outsideAppFolder.keys, ['user-photo']);
    });

    test('an encrypted copy is never deleted, whatever its name', () async {
      final sealed = await drive.upload(
        'finanzas-20260103-000000.zip',
        sealedWithZipName,
      );

      expect(await service.deleteUnencryptedBackups(), 0);

      expect(drive.meta.keys, [sealed.id]);
    });

    test('says whether there are any', () async {
      expect(await service.hasUnencryptedBackups(), isFalse);
      await service.backupNow();
      expect(await service.hasUnencryptedBackups(), isFalse);

      await drive.upload('finanzas-20260101-000000.zip', v1);

      expect(await service.hasUnencryptedBackups(), isTrue);
    });

    test('with no copies it deletes nothing', () async {
      expect(await service.deleteUnencryptedBackups(), 0);
      expect(drive.deletedIds, isEmpty);
    });

    test('without a session it throws NotSignedInException', () async {
      await drive.upload('finanzas-20260101-000000.zip', v1);
      account.email = null;

      await expectLater(
        service.deleteUnencryptedBackups(),
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
