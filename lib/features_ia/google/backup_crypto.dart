// Encrypted backup format v3 (T002, round 3): the v2 zip sealed with AES-256-GCM in
// 1 MiB blocks under a key derived with Argon2id. Pure Dart (`cryptography`).
//
// Layout: header, then the blocks. Every block is `ciphertext || 16-byte tag`, and its
// associated data is `header || block index (u32) || final flag (u8)`, so a changed
// byte, a reordered block or a missing final block fails authentication.
//
// Decryption streams block by block, but a block is only vouched for once it is read:
// whoever consumes the stream must not act on the output until it completes without error.
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:monekin/features_ia/google/backup_package.dart';

const _magic = [0x46, 0x49, 0x41, 0x33]; // FIA3
const _formatVersion = 1;
const _kdfArgon2id = 1;

const kSaltBytes = 16;
const kKeyBytes = 32;
const kNonceBytes = 12;
const kTagBytes = 16;
const kDefaultBlockSize = 1024 * 1024;

const _keyCheckBytes = 32;
const _headerSize =
    4 + 1 + 1 + 4 + 4 + 1 + kSaltBytes + 4 + kNonceBytes + _keyCheckBytes;
const _keyCheckOffset = _headerSize - _keyCheckBytes;

/// Bounds accepted when reading a header, so a hostile file cannot ask for a
/// derivation that exhausts the phone.
const _maxMemoryKiB = 128 * 1024;
const _maxIterations = 10;
const _maxParallelism = 4;
const _minBlockSize = 4096;
const _maxBlockSize = 16 * 1024 * 1024;

class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);
}

/// OWASP's minimum for Argon2id, measured in docs/USO.md §10.
const kDefaultKdfParams = KdfParams(
  memoryKiB: 19 * 1024,
  iterations: 2,
  parallelism: 1,
);

/// A derived key with the salt and cost it was derived with. Only this is kept on the
/// device, never the password.
class BackupKey {
  const BackupKey({
    required this.params,
    required this.salt,
    required this.key,
  });

  final KdfParams params;
  final Uint8List salt;
  final Uint8List key;
}

class BackupHeader {
  const BackupHeader({
    required this.params,
    required this.salt,
    required this.blockSize,
    required this.baseNonce,
  });

  final KdfParams params;
  final Uint8List salt;
  final int blockSize;
  final Uint8List baseNonce;
}

/// Gives the key for the header of a copy, or throws [InvalidBackupException].
typedef BackupKeyResolver = Future<Uint8List> Function(BackupHeader header);

bool isEncryptedBackup(List<int> bytes) {
  if (bytes.length < _magic.length) return false;
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) return false;
  }
  return true;
}

InvalidBackupException _invalid(InvalidBackupReason reason, String detail) =>
    InvalidBackupException(reason, detail);

Uint8List _randomBytes(int length, Random? random) {
  final source = random ?? Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => source.nextInt(256)));
}

Future<Uint8List> _argon2id(
  String password,
  Uint8List salt,
  KdfParams params,
) async {
  final key = await Argon2id(
    memory: params.memoryKiB,
    parallelism: params.parallelism,
    iterations: params.iterations,
    hashLength: kKeyBytes,
  ).deriveKeyFromPassword(password: password, nonce: salt);
  return Uint8List.fromList(await key.extractBytes());
}

/// Derives the key of [password] in another isolate, because it takes seconds.
Future<Uint8List> deriveKeyBytes(
  String password,
  Uint8List salt,
  KdfParams params,
) => Isolate.run(() => _argon2id(password, salt, params));

/// A new key from [password] with a fresh random salt.
Future<BackupKey> createBackupKey(
  String password, {
  KdfParams params = kDefaultKdfParams,
  Random? random,
}) async {
  final salt = _randomBytes(kSaltBytes, random);
  return BackupKey(
    params: params,
    salt: salt,
    key: await deriveKeyBytes(password, salt, params),
  );
}

/// Derives the key of a copy from [password], with the salt and cost of its header.
BackupKeyResolver resolverFromPassword(String password) =>
    (header) => deriveKeyBytes(password, header.salt, header.params);

/// Uses the stored key when the copy was sealed with it (same salt and cost);
/// otherwise the copy needs the password it was made with.
BackupKeyResolver resolverFromKey(BackupKey stored) => (header) async {
  if (header.params == stored.params && _equal(header.salt, stored.salt)) {
    return stored.key;
  }
  throw _invalid(
    InvalidBackupReason.passwordRequired,
    'the copy was sealed with another password',
  );
};

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

void _putU32(Uint8List out, int offset, int value) =>
    ByteData.sublistView(out).setUint32(offset, value);

Uint8List _headerBytes(BackupHeader h, Uint8List keyCheck) {
  final out = Uint8List(_headerSize);
  out.setRange(0, 4, _magic);
  out[4] = _formatVersion;
  out[5] = _kdfArgon2id;
  _putU32(out, 6, h.params.memoryKiB);
  _putU32(out, 10, h.params.iterations);
  out[14] = h.params.parallelism;
  out.setRange(15, 15 + kSaltBytes, h.salt);
  _putU32(out, 15 + kSaltBytes, h.blockSize);
  out.setRange(19 + kSaltBytes, 19 + kSaltBytes + kNonceBytes, h.baseNonce);
  out.setRange(_keyCheckOffset, _headerSize, keyCheck);
  return out;
}

BackupHeader _parseHeader(Uint8List bytes) {
  if (!isEncryptedBackup(bytes)) {
    throw _invalid(InvalidBackupReason.corrupt, 'not an encrypted copy');
  }
  final data = ByteData.sublistView(bytes);
  if (bytes[4] != _formatVersion || bytes[5] != _kdfArgon2id) {
    throw _invalid(
      InvalidBackupReason.corrupt,
      'unsupported encrypted copy v${bytes[4]}/${bytes[5]}',
    );
  }
  final params = KdfParams(
    memoryKiB: data.getUint32(6),
    iterations: data.getUint32(10),
    parallelism: bytes[14],
  );
  final blockSize = data.getUint32(15 + kSaltBytes);
  if (params.parallelism < 1 ||
      params.parallelism > _maxParallelism ||
      params.iterations < 1 ||
      params.iterations > _maxIterations ||
      params.memoryKiB < 8 * params.parallelism ||
      params.memoryKiB > _maxMemoryKiB ||
      blockSize < _minBlockSize ||
      blockSize > _maxBlockSize) {
    throw _invalid(InvalidBackupReason.corrupt, 'unreasonable header values');
  }
  return BackupHeader(
    params: params,
    salt: Uint8List.fromList(bytes.sublist(15, 15 + kSaltBytes)),
    blockSize: blockSize,
    baseNonce: Uint8List.fromList(
      bytes.sublist(19 + kSaltBytes, 19 + kSaltBytes + kNonceBytes),
    ),
  );
}

final _gcm = AesGcm.with256bits();
final _hmac = Hmac.sha256();

/// Proof that a key is the right one for a header, without touching any block. It
/// is what tells a wrong password from a changed file.
Future<Uint8List> _keyCheck(Uint8List key, Uint8List headerBytes) async {
  final input = Uint8List.fromList([
    ...'FIA3 key check'.codeUnits,
    ...headerBytes.sublist(0, _keyCheckOffset),
  ]);
  final mac = await _hmac.calculateMac(input, secretKey: SecretKey(key));
  return Uint8List.fromList(mac.bytes);
}

Uint8List _nonce(Uint8List base, int index) {
  final nonce = Uint8List.fromList(base);
  final tail = ByteData.sublistView(nonce, kNonceBytes - 4);
  tail.setUint32(0, tail.getUint32(0) ^ index);
  return nonce;
}

Uint8List _aad(Uint8List header, int index, bool last) {
  final out = Uint8List(header.length + 5)..setRange(0, header.length, header);
  _putU32(out, header.length, index);
  out[header.length + 4] = last ? 1 : 0;
  return out;
}

/// Seals [plain] under [key]. Emits the header and then one chunk per block; reads at
/// most one block ahead, so the memory used does not grow with the copy.
Stream<Uint8List> encryptBackupStream(
  Stream<List<int>> plain,
  BackupKey key, {
  int blockSize = kDefaultBlockSize,
  Random? random,
}) async* {
  final header = BackupHeader(
    params: key.params,
    salt: key.salt,
    blockSize: blockSize,
    baseNonce: _randomBytes(kNonceBytes, random),
  );
  final headerBytes = _headerBytes(header, Uint8List(_keyCheckBytes));
  final sealed = _headerBytes(header, await _keyCheck(key.key, headerBytes));
  yield sealed;

  final secret = SecretKey(key.key);
  var index = 0;

  Future<Uint8List> seal(Uint8List block, bool last) async {
    final box = await _gcm.encrypt(
      block,
      secretKey: secret,
      nonce: _nonce(header.baseNonce, index),
      aad: _aad(sealed, index, last),
    );
    index++;
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  var pending = BytesBuilder(copy: false);
  await for (final chunk in plain) {
    pending.add(chunk);
    while (pending.length > blockSize) {
      final all = pending.takeBytes();
      yield await seal(Uint8List.sublistView(all, 0, blockSize), false);
      pending = BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(all, blockSize));
    }
  }
  yield await seal(pending.takeBytes(), true);
}

Future<Uint8List> encryptBackupBytes(
  Uint8List plain,
  BackupKey key, {
  int blockSize = kDefaultBlockSize,
  Random? random,
}) async {
  final out = BytesBuilder(copy: false);
  await for (final chunk in encryptBackupStream(
    Stream.value(plain),
    key,
    blockSize: blockSize,
    random: random,
  )) {
    out.add(chunk);
  }
  return out.takeBytes();
}

/// Opens a sealed copy. Throws [InvalidBackupException] with `wrongPassword` when the
/// key is not the one the copy was sealed with, and `tampered` when a block fails
/// authentication (changed, reordered or truncated).
Stream<Uint8List> decryptBackupStream(
  Stream<List<int>> sealed,
  BackupKeyResolver resolveKey,
) async* {
  var pending = BytesBuilder(copy: false);
  Uint8List? headerBytes;
  BackupHeader? header;
  SecretKey? secret;
  var index = 0;

  Future<Uint8List> open(Uint8List block, bool last) async {
    if (block.length < kTagBytes) {
      throw _invalid(InvalidBackupReason.tampered, 'a block is too short');
    }
    final cut = block.length - kTagBytes;
    try {
      final clear = await _gcm.decrypt(
        SecretBox(
          Uint8List.sublistView(block, 0, cut),
          nonce: _nonce(header!.baseNonce, index),
          mac: Mac(Uint8List.sublistView(block, cut)),
        ),
        secretKey: secret!,
        aad: _aad(headerBytes!, index, last),
      );
      index++;
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw _invalid(
        InvalidBackupReason.tampered,
        'block $index failed authentication',
      );
    }
  }

  await for (final chunk in sealed) {
    pending.add(chunk);

    if (header == null && pending.length >= _headerSize) {
      final all = pending.takeBytes();
      headerBytes = Uint8List.sublistView(all, 0, _headerSize);
      header = _parseHeader(headerBytes);
      final key = await resolveKey(header);
      final expected = await _keyCheck(key, headerBytes);
      if (!_equal(
        expected,
        Uint8List.sublistView(headerBytes, _keyCheckOffset),
      )) {
        throw _invalid(InvalidBackupReason.wrongPassword, 'wrong password');
      }
      secret = SecretKey(key);
      pending = BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(all, _headerSize));
    }
    if (header == null) continue;

    final full = header.blockSize + kTagBytes;
    while (pending.length > full) {
      final all = pending.takeBytes();
      yield await open(Uint8List.sublistView(all, 0, full), false);
      pending = BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(all, full));
    }
  }

  if (header == null) {
    throw _invalid(InvalidBackupReason.corrupt, 'the copy ends in its header');
  }
  if (pending.isEmpty) {
    throw _invalid(InvalidBackupReason.tampered, 'the final block is missing');
  }
  yield await open(pending.takeBytes(), true);
}

Future<Uint8List> decryptBackupBytes(
  Uint8List sealed,
  BackupKeyResolver resolveKey,
) async {
  final out = BytesBuilder(copy: false);
  await for (final chunk in decryptBackupStream(
    Stream.value(sealed),
    resolveKey,
  )) {
    out.add(chunk);
  }
  return out.takeBytes();
}
