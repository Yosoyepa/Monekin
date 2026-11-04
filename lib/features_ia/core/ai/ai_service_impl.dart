import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/openai_compatible_client.dart';
import 'package:path_provider/path_provider.dart';

const aiPresets = <AiProviderId, AiProviderConfig>{
  AiProviderId.gemini: AiProviderConfig(
    provider: AiProviderId.gemini,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
    model: 'gemini-flash-lite-latest',
  ),
  AiProviderId.deepseek: AiProviderConfig(
    provider: AiProviderId.deepseek,
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-flash',
  ),
  AiProviderId.openrouter: AiProviderConfig(
    provider: AiProviderId.openrouter,
    baseUrl: 'https://openrouter.ai/api/v1',
    model: '',
  ),
  AiProviderId.custom: AiProviderConfig(
    provider: AiProviderId.custom,
    baseUrl: '',
    model: '',
  ),
};

class AiServiceImpl implements AiService {
  AiServiceImpl({
    Future<File> Function()? configFile,
    FlutterSecureStorage? storage,
  }) : _configFile = configFile ?? _defaultFile,
       _storage = storage ?? const FlutterSecureStorage();

  final Future<File> Function() _configFile;
  final FlutterSecureStorage _storage;

  /// Name used before keys were bound to a destination.
  static const _legacyKeyName = 'ai_api_key';

  /// Secure-storage name of the key for [config]. A key is only sent to the provider and origin (scheme, host and port) it was saved for.
  static String keyNameFor(AiProviderConfig config) =>
      'ai_key:${config.provider.name}:${_originOf(config.baseUrl)}';

  /// Name of a key moved from an older version: it is kept but not used until the user pastes it again.
  static String _pendingNameFor(AiProviderConfig config) =>
      'ai_key_pending:${config.provider.name}:${_originOf(config.baseUrl)}';

  static String _originOf(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || uri.host.isEmpty) return '';
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:${uri.port}';
  }

  static Future<File> _defaultFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}ai_settings.json',
  );

  Future<AiProviderConfig> loadConfig() async {
    final file = await _configFile();
    if (!await file.exists()) return aiPresets[AiProviderId.gemini]!;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final provider = AiProviderId.values.byName(data['provider'] as String);
      return AiProviderConfig(
        provider: provider,
        baseUrl: data['baseUrl'] as String,
        model: data['model'] as String,
      );
    } on FormatException {
      return aiPresets[AiProviderId.gemini]!;
    } on TypeError {
      return aiPresets[AiProviderId.gemini]!;
    } on ArgumentError {
      return aiPresets[AiProviderId.gemini]!;
    }
  }

  Future<void> saveConfig(AiProviderConfig config) async {
    await _migrateLegacyKey();
    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'provider': config.provider.name,
        'baseUrl': config.baseUrl,
        'model': config.model,
      }),
    );
  }

  /// Moves the key saved before keys were per destination to the settings saved now, as a key to confirm.
  Future<void> _migrateLegacyKey() async {
    final legacy = await _storage.read(key: _legacyKeyName);
    if (legacy == null) return;
    if (legacy.trim().isNotEmpty) {
      await _storage.write(
        key: _pendingNameFor(await loadConfig()),
        value: legacy.trim(),
      );
    }
    await _storage.delete(key: _legacyKeyName);
  }

  /// The confirmed key saved for [config], or null. Defaults to the saved settings.
  Future<String?> _readKey(AiProviderConfig? config) async {
    await _migrateLegacyKey();
    final key = await _storage.read(
      key: keyNameFor(config ?? await loadConfig()),
    );
    return key == null || key.trim().isEmpty ? null : key;
  }

  /// Saves [key] for the provider and origin of [config] (the saved settings when null). Confirms a moved key.
  Future<void> saveKey(String key, [AiProviderConfig? config]) async {
    await _migrateLegacyKey();
    final destination = config ?? await loadConfig();
    await _storage.write(key: keyNameFor(destination), value: key.trim());
    await _storage.delete(key: _pendingNameFor(destination));
  }

  Future<void> deleteKey([AiProviderConfig? config]) async {
    await _migrateLegacyKey();
    final destination = config ?? await loadConfig();
    await _storage.delete(key: keyNameFor(destination));
    await _storage.delete(key: _pendingNameFor(destination));
  }

  /// True when a confirmed key is saved for [config].
  Future<bool> hasKey([AiProviderConfig? config]) async =>
      await _readKey(config) != null;

  /// True when a key moved from an older version waits for the user to paste it once to confirm it.
  Future<bool> hasKeyToConfirm([AiProviderConfig? config]) async {
    await _migrateLegacyKey();
    final key = await _storage.read(
      key: _pendingNameFor(config ?? await loadConfig()),
    );
    return key != null && key.trim().isNotEmpty;
  }

  @override
  Future<bool> isConfigured() async {
    if (AiService.debugClientOverride != null) return true;
    final config = await loadConfig();
    return isAllowedProviderUrl(config.baseUrl) &&
        config.model.trim().isNotEmpty &&
        await hasKey(config);
  }

  @override
  Future<AiClient> client() async => clientFor(await loadConfig());

  /// The client for exactly [config]: the settings are not read again, so the destination cannot change under it.
  Future<AiClient> clientFor(AiProviderConfig config) async {
    final override = AiService.debugClientOverride;
    if (override != null) return override;
    final key = await _readKey(config);
    if (!isAllowedProviderUrl(config.baseUrl) ||
        config.model.trim().isEmpty ||
        key == null) {
      throw const AiException(
        AiErrorKind.notConfigured,
        'AI is not configured',
      );
    }
    return OpenAiCompatibleClient(
      baseUrl: config.baseUrl,
      apiKey: key,
      model: config.model,
    );
  }

  Future<AiClient> clientForModels(AiProviderConfig config) async {
    final override = AiService.debugClientOverride;
    if (override != null) return override;
    final key = await _readKey(config);
    if (key == null || !isAllowedProviderUrl(config.baseUrl)) {
      throw const AiException(
        AiErrorKind.notConfigured,
        'AI is not configured',
      );
    }
    return OpenAiCompatibleClient(
      baseUrl: config.baseUrl,
      apiKey: key,
      model: config.model,
    );
  }
}
