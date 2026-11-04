import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
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

/// Recomputes the plain digest at the end of a header edited by a test.
Future<void> fixDigest(Uint8List sealed) async {
  const digestOffset = kBackupHeaderSize - 32;
  final hash = await Sha256().hash(sealed.sublist(0, digestOffset));
  sealed.setRange(digestOffset, kBackupHeaderSize, hash.bytes);
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
      const full = 4096 + 16;
      for (final offset in [
        kBackupHeaderSize,
        kBackupHeaderSize + full - 1,
        kBackupHeaderSize + full,
        kBackupHeaderSize + 2 * full + 3,
        sealed.length - 1,
      ]) {
        final changed = Uint8List.fromList(sealed)..[offset] ^= 0x01;
        await expectReason(() => open(changed), InvalidBackupReason.tampered);
      }
    });

    test('a changed header is a changed file, in every field', () async {
      // Every byte of the header but the format version, which is its own error.
      for (var offset = 6; offset < kBackupHeaderSize; offset += 7) {
        final changed = Uint8List.fromList(sealed)..[offset] ^= 0x01;
        await expectReason(() => open(changed), InvalidBackupReason.tampered);
      }
      for (final offset in [6, 14, 15, 31, 35, 66, 67, 70, 71, 102, 103, 134]) {
        final changed = Uint8List.fromList(sealed)..[offset] ^= 0x80;
        await expectReason(() => open(changed), InvalidBackupReason.tampered);
      }
    });

    test('another format version is not a changed file', () async {
      final changed = Uint8List.fromList(sealed)..[4] = 1;
      await expectReason(() => open(changed), InvalidBackupReason.corrupt);
    });

    test(
      'a header edited with its digest fixed cannot tell from a wrong password',
      () async {
        final edited = Uint8List.fromList(sealed)..[40] ^= 0x01;
        await fixDigest(edited);

        await expectReason(
          () => open(edited),
          InvalidBackupReason.wrongPassword,
        );
      },
    );

    test('reordered blocks fail', () async {
      const full = 4096 + 16;
      final swapped = Uint8List.fromList(sealed);
      swapped.setRange(
        kBackupHeaderSize,
        kBackupHeaderSize + full,
        sealed.sublist(kBackupHeaderSize + full, kBackupHeaderSize + 2 * full),
      );
      swapped.setRange(
        kBackupHeaderSize + full,
        kBackupHeaderSize + 2 * full,
        sealed.sublist(kBackupHeaderSize, kBackupHeaderSize + full),
      );

      await expectReason(() => open(swapped), InvalidBackupReason.tampered);
    });

    test('a copy without its final block fails', () async {
      const full = 4096 + 16;
      final cut = sealed.sublist(0, kBackupHeaderSize + 2 * full);

      await expectReason(() => open(cut), InvalidBackupReason.tampered);
      await expectReason(
        () => open(sealed.sublist(0, kBackupHeaderSize + full)),
        InvalidBackupReason.tampered,
      );
      await expectReason(
        () => open(sealed.sublist(0, kBackupHeaderSize)),
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
      await fixDigest(hostile);

      await expectReason(() => open(hostile), InvalidBackupReason.corrupt);
    });

    test('appended bytes fail', () async {
      final longer = Uint8List.fromList([...sealed, 1, 2, 3]);
      await expectReason(() => open(longer), InvalidBackupReason.tampered);
    });
  });

  group('keys and nonces', () {
    test('two copies with the same master key have different keys', () async {
      final a = await encryptBackupBytes(sample(100), key);
      final b = await encryptBackupBytes(sample(100), key);
      final headerA = readBackupHeader(a);
      final headerB = readBackupHeader(b);

      expect(headerA.fileId, hasLength(kFileIdBytes));
      expect(headerA.fileId, isNot(headerB.fileId));

      final keysA = await deriveFileKeys(key.key, headerA.fileId);
      final keysB = await deriveFileKeys(key.key, headerB.fileId);
      expect(keysA.enc, isNot(keysB.enc));
      expect(keysA.check, isNot(keysB.check));
    });

    test(
      'the key that checks the password is not the one that encrypts',
      () async {
        final header = readBackupHeader(
          await encryptBackupBytes(sample(10), key),
        );
        final keys = await deriveFileKeys(key.key, header.fileId);

        expect(keys.check, isNot(keys.enc));
        expect(keys.enc, isNot(key.key));
        expect(keys.check, isNot(key.key));
        expect(keys.enc, hasLength(kKeyBytes));
        expect(keys.check, hasLength(kKeyBytes));
      },
    );

    test(
      'the keys of a copy depend on its file id and on the master key',
      () async {
        final fileId = sample(kFileIdBytes, 1);
        final first = await deriveFileKeys(key.key, fileId);
        final again = await deriveFileKeys(key.key, fileId);
        final otherId = await deriveFileKeys(key.key, sample(kFileIdBytes, 2));
        final otherMaster = await deriveFileKeys(sample(kKeyBytes, 3), fileId);

        expect(again.enc, first.enc);
        expect(otherId.enc, isNot(first.enc));
        expect(otherMaster.enc, isNot(first.enc));
      },
    );

    test('the nonce of every block is different', () {
      final prefix = Uint8List.fromList([9, 8, 7, 6]);
      final seen = <String>{};
      for (var i = 0; i < 20000; i++) {
        final nonce = backupBlockNonce(prefix, i);
        expect(nonce, hasLength(kNonceBytes));
        expect(nonce.sublist(0, kNoncePrefixBytes), prefix);
        seen.add(nonce.join(','));
      }
      expect(seen, hasLength(20000));

      final big = backupBlockNonce(prefix, 0x01020304);
      expect(big.sublist(4, 8), [0, 0, 0, 0], reason: '64-bit counter');
      expect(big.sublist(8), [1, 2, 3, 4]);
      expect(
        backupBlockNonce(Uint8List(4), 5),
        isNot(backupBlockNonce(prefix, 5)),
      );
    });

    test(
      'equal plaintext blocks of one copy seal to different bytes',
      () async {
        final sealed = await encryptBackupBytes(
          Uint8List(3 * 4096 + 10),
          key,
          blockSize: 4096,
        );
        const full = 4096 + 16;
        final blocks = [
          for (var i = 0; i < 3; i++)
            sealed
                .sublist(
                  kBackupHeaderSize + i * full,
                  kBackupHeaderSize + i * full + 4096,
                )
                .join(','),
        ];
        expect(blocks.toSet(), hasLength(3));
      },
    );

    test('the same plaintext in two copies seals to different bytes', () async {
      final plain = Uint8List(4096);
      final a = await encryptBackupBytes(plain, key, blockSize: 4096);
      final b = await encryptBackupBytes(plain, key, blockSize: 4096);

      expect(
        a.sublist(kBackupHeaderSize, kBackupHeaderSize + 4096),
        isNot(b.sublist(kBackupHeaderSize, kBackupHeaderSize + 4096)),
      );
    });

    test('the header carries no key, only public parameters', () async {
      final sealed = await encryptBackupBytes(sample(10), key);
      final text = sealed.join(',');

      expect(text, isNot(contains(key.key.join(','))));
      final header = readBackupHeader(sealed);
      final keys = await deriveFileKeys(key.key, header.fileId);
      expect(text, isNot(contains(keys.enc.join(','))));
      expect(text, isNot(contains(keys.check.join(','))));
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
