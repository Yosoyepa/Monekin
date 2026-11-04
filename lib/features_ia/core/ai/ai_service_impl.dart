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

const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

/// The API key may only travel to https, or to http on this device or the emulator.
bool isAllowedProviderUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  return uri.scheme == 'https' ||
      (uri.scheme == 'http' && _localHosts.contains(uri.host));
}

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

  /// Secure-storage name of the key for [config]. A key is only sent to the provider and host it was saved for.
  static String keyNameFor(AiProviderConfig config) {
    final uri = Uri.tryParse(config.baseUrl.trim());
    final host = uri == null || uri.host.isEmpty
        ? ''
        : '${uri.host.toLowerCase()}${uri.hasPort ? ':${uri.port}' : ''}';
    return 'ai_key:${config.provider.name}:$host';
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

  /// Binds the key saved before keys were per destination to the provider and host saved now.
  Future<void> _migrateLegacyKey() async {
    final legacy = await _storage.read(key: _legacyKeyName);
    if (legacy == null) return;
    if (legacy.trim().isNotEmpty) {
      await _storage.write(
        key: keyNameFor(await loadConfig()),
        value: legacy.trim(),
      );
    }
    await _storage.delete(key: _legacyKeyName);
  }

  /// The key saved for [config], or null. Defaults to the saved settings.
  Future<String?> _readKey(AiProviderConfig? config) async {
    await _migrateLegacyKey();
    final key = await _storage.read(
      key: keyNameFor(config ?? await loadConfig()),
    );
    return key == null || key.trim().isEmpty ? null : key;
  }

  /// Saves [key] for the provider and host of [config] (the saved settings when null).
  Future<void> saveKey(String key, [AiProviderConfig? config]) async {
    await _migrateLegacyKey();
    await _storage.write(
      key: keyNameFor(config ?? await loadConfig()),
      value: key.trim(),
    );
  }

  Future<void> deleteKey([AiProviderConfig? config]) async {
    await _migrateLegacyKey();
    await _storage.delete(key: keyNameFor(config ?? await loadConfig()));
  }

  Future<bool> hasKey([AiProviderConfig? config]) async =>
      await _readKey(config) != null;

  @override
  Future<bool> isConfigured() async {
    if (AiService.debugClientOverride != null) return true;
    final config = await loadConfig();
    return isAllowedProviderUrl(config.baseUrl) &&
        config.model.trim().isNotEmpty &&
        await hasKey(config);
  }

  @override
  Future<AiClient> client() async {
    final override = AiService.debugClientOverride;
    if (override != null) return override;
    if (!await isConfigured()) {
      throw const AiException(
        AiErrorKind.notConfigured,
        'AI is not configured',
      );
    }
    final config = await loadConfig();
    return OpenAiCompatibleClient(
      baseUrl: config.baseUrl,
      apiKey: (await _readKey(config))!,
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
