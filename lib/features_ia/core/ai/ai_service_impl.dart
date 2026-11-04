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
  static const _keyName = 'ai_api_key';

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

  Future<void> saveKey(String key) =>
      _storage.write(key: _keyName, value: key.trim());
  Future<void> deleteKey() => _storage.delete(key: _keyName);
  Future<bool> hasKey() async =>
      (await _storage.read(key: _keyName))?.trim().isNotEmpty ?? false;

  @override
  Future<bool> isConfigured() async {
    if (AiService.debugClientOverride != null) return true;
    final config = await loadConfig();
    final uri = Uri.tryParse(config.baseUrl);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        config.model.trim().isNotEmpty &&
        await hasKey();
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
      apiKey: (await _storage.read(key: _keyName))!,
      model: config.model,
    );
  }

  Future<AiClient> clientForModels(AiProviderConfig config) async {
    final override = AiService.debugClientOverride;
    if (override != null) return override;
    final key = await _storage.read(key: _keyName);
    final uri = Uri.tryParse(config.baseUrl);
    if (key == null ||
        key.trim().isEmpty ||
        uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
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
