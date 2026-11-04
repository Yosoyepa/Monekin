// Where the derived backup key lives (T002, round 3): the platform's secure storage.
// Only the key, the salt and the cost of its derivation are kept; the password never.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';

abstract class BackupKeyStore {
  Future<BackupKey?> load();

  Future<void> save(BackupKey key);

  Future<void> clear();
}

class SecureBackupKeyStore implements BackupKeyStore {
  SecureBackupKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'finanzas_backup_key';

  final FlutterSecureStorage _storage;

  @override
  Future<BackupKey?> load() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return BackupKey(
        params: KdfParams(
          memoryKiB: json['memoryKiB'] as int,
          iterations: json['iterations'] as int,
          parallelism: json['parallelism'] as int,
        ),
        salt: Uint8List.fromList(base64Decode(json['salt'] as String)),
        key: Uint8List.fromList(base64Decode(json['key'] as String)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(BackupKey key) => _storage.write(
    key: storageKey,
    value: jsonEncode({
      'memoryKiB': key.params.memoryKiB,
      'iterations': key.params.iterations,
      'parallelism': key.params.parallelism,
      'salt': base64Encode(key.salt),
      'key': base64Encode(key.key),
    }),
  );

  @override
  Future<void> clear() => _storage.delete(key: storageKey);
}

class MemoryBackupKeyStore implements BackupKeyStore {
  BackupKey? _key;

  @override
  Future<BackupKey?> load() async => _key;

  @override
  Future<void> save(BackupKey key) async => _key = key;

  @override
  Future<void> clear() async => _key = null;
}
