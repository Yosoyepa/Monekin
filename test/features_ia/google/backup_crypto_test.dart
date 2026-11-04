import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_key_store.dart';
import 'package:monekin/features_ia/google/backup_package.dart';

/// Cheap derivation so the tests stay fast; the real cost is measured separately.
const testParams = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

Uint8List sample(int length, [int seed = 7]) {
  final random = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

Future<void> expectReason(
  Future<Object?> Function() action,
  InvalidBackupReason reason,
) async {
  await expectLater(
    action(),
    throwsA(
      isA<InvalidBackupException>().having((e) => e.reason, 'reason', reason),
    ),
  );
}

void main() {
  late BackupKey key;
  const password = 'correct horse battery';

  setUpAll(() async {
    key = await createBackupKey(password, params: testParams);
  });

  group('round trip', () {
    test('a small zip comes back exactly', () async {
      final plain = sample(5000);
      final sealed = await encryptBackupBytes(plain, key);

      expect(isEncryptedBackup(sealed), isTrue);
      expect(sealed, isNot(contains(plain.sublist(0, 32))));
      expect(await decryptBackupBytes(sealed, resolverFromKey(key)), plain);
    });

    test('a copy of several blocks (3.5 MiB) comes back exactly', () async {
      final plain = sample(3 * 1024 * 1024 + 512 * 1024);
      final sealed = await encryptBackupBytes(plain, key);

      expect(sealed.length, greaterThan(plain.length));
      expect(await decryptBackupBytes(sealed, resolverFromKey(key)), plain);
    });

    test('empty and block-multiple inputs have a final block', () async {
      for (final length in [0, 4096, 8192]) {
        final plain = sample(length);
        final sealed = await encryptBackupBytes(plain, key, blockSize: 4096);
        expect(
          await decryptBackupBytes(sealed, resolverFromKey(key)),
          plain,
          reason: 'length $length',
        );
      }
    });

    test('streams in odd chunks give the same result', () async {
      final plain = sample(20000);
      final chunks = [
        for (var i = 0; i < plain.length; i += 777)
          plain.sublist(i, min(i + 777, plain.length)),
      ];
      final sealed = BytesBuilder();
      await for (final c in encryptBackupStream(
        Stream.fromIterable(chunks),
        key,
        blockSize: 4096,
      )) {
        sealed.add(c);
      }
      final bytes = sealed.takeBytes();

      final out = BytesBuilder();
      await for (final c in decryptBackupStream(
        Stream.fromIterable([
          for (var i = 0; i < bytes.length; i += 1000)
            bytes.sublist(i, min(i + 1000, bytes.length)),
        ]),
        resolverFromKey(key),
      )) {
        out.add(c);
      }
      expect(out.takeBytes(), plain);
    });

    test(
      'the password opens it using the salt and cost in the header',
      () async {
        final sealed = await encryptBackupBytes(sample(3000), key);

        expect(
          await decryptBackupBytes(sealed, resolverFromPassword(password)),
          sample(3000),
        );
      },
    );

    test('two copies of the same data differ (random nonce)', () async {
      final plain = sample(3000);
      expect(
        await encryptBackupBytes(plain, key),
        isNot(await encryptBackupBytes(plain, key)),
      );
    });
  });

  group('wrong password and tampering', () {
    late Uint8List plain;
    late Uint8List sealed;

    setUpAll(() async {
      plain = sample(10000);
      sealed = await encryptBackupBytes(plain, key, blockSize: 4096);
    });

    Future<Object?> open(Uint8List bytes) =>
        decryptBackupBytes(bytes, resolverFromPassword(password));

    test('a wrong password is its own error', () async {
      await expectReason(
        () => decryptBackupBytes(sealed, resolverFromPassword('not the one')),
        InvalidBackupReason.wrongPassword,
      );
    });

    test('a key of another password asks for the password', () async {
      final other = await createBackupKey(
        'another long password',
        params: testParams,
      );
      await expectReason(
        () => decryptBackupBytes(sealed, resolverFromKey(other)),
        InvalidBackupReason.passwordRequired,
      );
    });

    test('a changed byte in any block fails', () async {
      const headerSize = 79;
      const full = 4096 + 16;
      for (final offset in [
        headerSize,
        headerSize + full - 1,
        headerSize + full,
        headerSize + 2 * full + 3,
        sealed.length - 1,
      ]) {
        final changed = Uint8List.fromList(sealed)..[offset] ^= 0x01;
        await expectReason(() => open(changed), InvalidBackupReason.tampered);
      }
    });

    test('a changed header fails', () async {
      for (final offset in [4, 20, 40, 47, 60]) {
        final changed = Uint8List.fromList(sealed)..[offset] ^= 0x01;
        await expectLater(
          open(changed),
          throwsA(isA<InvalidBackupException>()),
        );
      }
    });

    test('reordered blocks fail', () async {
      const headerSize = 79;
      const full = 4096 + 16;
      final swapped = Uint8List.fromList(sealed);
      swapped.setRange(
        headerSize,
        headerSize + full,
        sealed.sublist(headerSize + full, headerSize + 2 * full),
      );
      swapped.setRange(
        headerSize + full,
        headerSize + 2 * full,
        sealed.sublist(headerSize, headerSize + full),
      );

      await expectReason(() => open(swapped), InvalidBackupReason.tampered);
    });

    test('a copy without its final block fails', () async {
      const headerSize = 79;
      const full = 4096 + 16;
      final cut = sealed.sublist(0, headerSize + 2 * full);

      await expectReason(() => open(cut), InvalidBackupReason.tampered);
      await expectReason(
        () => open(sealed.sublist(0, headerSize + full)),
        InvalidBackupReason.tampered,
      );
      await expectReason(
        () => open(sealed.sublist(0, headerSize)),
        InvalidBackupReason.tampered,
      );
    });

    test('a copy cut inside the header fails', () async {
      await expectReason(
        () => open(sealed.sublist(0, 30)),
        InvalidBackupReason.corrupt,
      );
    });

    test('a hostile header cannot ask for an enormous derivation', () async {
      final hostile = Uint8List.fromList(sealed);
      ByteData.sublistView(hostile).setUint32(6, 0x7fffffff);

      await expectReason(() => open(hostile), InvalidBackupReason.corrupt);
    });

    test('appended bytes fail', () async {
      final longer = Uint8List.fromList([...sealed, 1, 2, 3]);
      await expectReason(() => open(longer), InvalidBackupReason.tampered);
    });
  });

  group('secure storage', () {
    test('only the derived key is kept, never the password', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const longPassword = 'my very private backup password 2026';
      final derived = await createBackupKey(longPassword, params: testParams);

      final store = SecureBackupKeyStore();
      await store.save(derived);

      final everything = await const FlutterSecureStorage().readAll();
      expect(everything, isNotEmpty);
      for (final entry in everything.entries) {
        expect(entry.key, isNot(contains(longPassword)));
        expect(entry.value, isNot(contains(longPassword)));
      }

      final loaded = (await store.load())!;
      expect(loaded.key, derived.key);
      expect(loaded.salt, derived.salt);
      expect(loaded.params, derived.params);

      final sealed = await encryptBackupBytes(sample(100), loaded);
      expect(
        await decryptBackupBytes(sealed, resolverFromPassword(longPassword)),
        sample(100),
      );

      await store.clear();
      expect(await store.load(), isNull);
    });
  });
}
