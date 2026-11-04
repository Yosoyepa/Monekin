// Encrypted backup format v3 (T002, round 4): the v2 zip sealed with AES-256-GCM in
// 1 MiB blocks. Pure Dart (`cryptography`).
//
// Keys. The password gives a *master* key with Argon2id; only the master key is kept
// on the phone. Every copy carries a random 32-byte `fileId`, and its keys are
//   encKey   = HKDF-SHA256(master, salt = fileId, info = "FIA3 enc")
//   checkKey = HKDF-SHA256(master, salt = fileId, info = "FIA3 check")
// so two copies made with the same password never share an encryption key, and the
// key that proves the password is not the key that encrypts.
//
// Nonces. A block's 96-bit nonce is 4 random bytes fixed for the file plus the 64-bit
// block counter, so it cannot repeat inside a copy, and a different file has a
// different key.
//
// Layout: header, then the blocks. Every block is `ciphertext || 16-byte tag`, and its
// associated data is `header || block index (u32) || final flag (u8)`, so a changed
// byte, a reordered block or a missing final block fails authentication.
//
// Header. `keyCheck` is an HMAC of the fields before it under `checkKey`: it tells a
// wrong password from a right one. `digest` is a plain SHA-256 of everything before
// it, with no secret: it catches a header that was damaged or edited by someone who
// did not recompute it, and that is reported as a changed file. Whoever also fixes the
// digest is indistinguishable from a wrong password, and the blocks still do not open.
//
// Decryption streams block by block, but a block is only vouched for once it is read:
// whoever consumes the stream must not act on the output until it completes without error.
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:monekin/features_ia/google/backup_package.dart';

const _magic = [0x46, 0x49, 0x41, 0x33]; // FIA3
const _formatVersion = 2;
const _kdfArgon2id = 1;

const kSaltBytes = 16;
const kKeyBytes = 32;
const kFileIdBytes = 32;
const kNoncePrefixBytes = 4;
const kNonceBytes = 12;
const kTagBytes = 16;
const kDefaultBlockSize = 1024 * 1024;

const _keyCheckBytes = 32;
const _digestBytes = 32;

const _saltOffset = 15;
const _blockSizeOffset = _saltOffset + kSaltBytes;
const _fileIdOffset = _blockSizeOffset + 4;
const _noncePrefixOffset = _fileIdOffset + kFileIdBytes;
const _keyCheckOffset = _noncePrefixOffset + kNoncePrefixBytes;
const _digestOffset = _keyCheckOffset + _keyCheckBytes;

/// Size of the header of every copy.
const kBackupHeaderSize = _digestOffset + _digestBytes;

/// The block counter has 64 bits in the nonce; blocks are numbered from a u32.
const _maxBlocks = 0xffffffff;

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

/// The master key derived from the password, with the salt and cost it was derived
/// with. Only this is kept on the device, never the password. Each copy derives its
/// own keys from it.
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
    required this.fileId,
    required this.noncePrefix,
  });

  final KdfParams params;
  final Uint8List salt;
  final int blockSize;
  final Uint8List fileId;
  final Uint8List noncePrefix;
}

/// The two keys of one copy.
class BackupFileKeys {
  const BackupFileKeys({required this.enc, required this.check});

  final Uint8List enc;
  final Uint8List check;
}

/// Gives the master key for the header of a copy, or throws [InvalidBackupException].
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

/// Derives the master key of [password] in another isolate, because it takes seconds.
Future<Uint8List> deriveKeyBytes(
  String password,
  Uint8List salt,
  KdfParams params,
) => Isolate.run(() => _argon2id(password, salt, params));

/// A new master key from [password] with a fresh random salt.
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

/// Derives the master key of a copy from [password], with the salt and cost of its
/// header.
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

final _gcm = AesGcm.with256bits();
final _hmac = Hmac.sha256();
final _sha256 = Sha256();

Future<Uint8List> _hkdf(Uint8List master, Uint8List fileId, String info) async {
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: kKeyBytes)
      .deriveKey(
        secretKey: SecretKey(master),
        nonce: fileId,
        info: utf8.encode(info),
      );
  return Uint8List.fromList(await key.extractBytes());
}

/// The keys of the copy identified by [fileId], from the [master] key.
@visibleForTesting
Future<BackupFileKeys> deriveFileKeys(
  Uint8List master,
  Uint8List fileId,
) async => BackupFileKeys(
  enc: await _hkdf(master, fileId, 'FIA3 enc'),
  check: await _hkdf(master, fileId, 'FIA3 check'),
);

/// The 96-bit nonce of block [index]: the file's 4 bytes and a 64-bit counter.
@visibleForTesting
Uint8List backupBlockNonce(Uint8List noncePrefix, int index) {
  final nonce = Uint8List(kNonceBytes)
    ..setRange(0, kNoncePrefixBytes, noncePrefix);
  ByteData.sublistView(nonce).setUint32(kNoncePrefixBytes + 4, index);
  return nonce;
}

Uint8List _headerBytes(BackupHeader h) {
  final out = Uint8List(kBackupHeaderSize);
  out.setRange(0, 4, _magic);
  out[4] = _formatVersion;
  out[5] = _kdfArgon2id;
  _putU32(out, 6, h.params.memoryKiB);
  _putU32(out, 10, h.params.iterations);
  out[14] = h.params.parallelism;
  out.setRange(_saltOffset, _saltOffset + kSaltBytes, h.salt);
  _putU32(out, _blockSizeOffset, h.blockSize);
  out.setRange(_fileIdOffset, _fileIdOffset + kFileIdBytes, h.fileId);
  out.setRange(
    _noncePrefixOffset,
    _noncePrefixOffset + kNoncePrefixBytes,
    h.noncePrefix,
  );
  return out;
}

Future<Uint8List> _keyCheck(Uint8List checkKey, Uint8List header) async {
  final mac = await _hmac.calculateMac(
    Uint8List.sublistView(header, 0, _keyCheckOffset),
    secretKey: SecretKey(checkKey),
  );
  return Uint8List.fromList(mac.bytes);
}

Future<Uint8List> _digest(Uint8List header) async {
  final hash = await _sha256.hash(
    Uint8List.sublistView(header, 0, _digestOffset),
  );
  return Uint8List.fromList(hash.bytes);
}

/// Rejects what is not a header of this format: wrong magic, cut short or another
/// version.
void _requireFormat(Uint8List bytes) {
  if (!isEncryptedBackup(bytes)) {
    throw _invalid(InvalidBackupReason.corrupt, 'not an encrypted copy');
  }
  if (bytes.length < kBackupHeaderSize) {
    throw _invalid(InvalidBackupReason.corrupt, 'the copy ends in its header');
  }
  if (bytes[4] != _formatVersion || bytes[5] != _kdfArgon2id) {
    throw _invalid(
      InvalidBackupReason.corrupt,
      'unsupported encrypted copy v${bytes[4]}/${bytes[5]}',
    );
  }
}

/// Reads the header of a copy without a key, and rejects a header that is damaged
/// (`tampered`), is not of this format or asks for unreasonable costs (`corrupt`).
BackupHeader readBackupHeader(Uint8List bytes) {
  _requireFormat(bytes);
  final data = ByteData.sublistView(bytes);
  final params = KdfParams(
    memoryKiB: data.getUint32(6),
    iterations: data.getUint32(10),
    parallelism: bytes[14],
  );
  final blockSize = data.getUint32(_blockSizeOffset);
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
    salt: Uint8List.fromList(
      bytes.sublist(_saltOffset, _saltOffset + kSaltBytes),
    ),
    blockSize: blockSize,
    fileId: Uint8List.fromList(
      bytes.sublist(_fileIdOffset, _fileIdOffset + kFileIdBytes),
    ),
    noncePrefix: Uint8List.fromList(
      bytes.sublist(_noncePrefixOffset, _noncePrefixOffset + kNoncePrefixBytes),
    ),
  );
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
    fileId: _randomBytes(kFileIdBytes, random),
    noncePrefix: _randomBytes(kNoncePrefixBytes, random),
  );
  final keys = await deriveFileKeys(key.key, header.fileId);

  final sealed = _headerBytes(header);
  sealed.setRange(
    _keyCheckOffset,
    _digestOffset,
    await _keyCheck(keys.check, sealed),
  );
  sealed.setRange(_digestOffset, kBackupHeaderSize, await _digest(sealed));
  yield sealed;

  final secret = SecretKey(keys.enc);
  var index = 0;

  Future<Uint8List> seal(Uint8List block, bool last) async {
    if (index >= _maxBlocks) {
      throw StateError('too many blocks for one copy');
    }
    final box = await _gcm.encrypt(
      block,
      secretKey: secret,
      nonce: backupBlockNonce(header.noncePrefix, index),
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

/// Opens a sealed copy. Throws [InvalidBackupException] with `tampered` when the
/// header does not match its digest or a block fails authentication (changed,
/// reordered or truncated), and `wrongPassword` when the key is not the one the copy
/// was sealed with.
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
          nonce: backupBlockNonce(header!.noncePrefix, index),
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

    if (header == null && pending.length >= kBackupHeaderSize) {
      final all = pending.takeBytes();
      headerBytes = Uint8List.sublistView(all, 0, kBackupHeaderSize);
      _requireFormat(headerBytes);
      if (!_equal(
        await _digest(headerBytes),
        Uint8List.sublistView(headerBytes, _digestOffset),
      )) {
        throw _invalid(
          InvalidBackupReason.tampered,
          'the header does not match its digest',
        );
      }
      header = readBackupHeader(headerBytes);

      final master = await resolveKey(header);
      final keys = await deriveFileKeys(master, header.fileId);
      final expected = await _keyCheck(keys.check, headerBytes);
      if (!_equal(
        expected,
        Uint8List.sublistView(headerBytes, _keyCheckOffset, _digestOffset),
      )) {
        throw _invalid(InvalidBackupReason.wrongPassword, 'wrong password');
      }
      secret = SecretKey(keys.enc);
      pending = BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(all, kBackupHeaderSize));
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
