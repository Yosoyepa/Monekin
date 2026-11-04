import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configuration files never contain the saved key', () async {
    final directory = await Directory.systemTemp.createTemp('ai-private-');
    addTearDown(() async => directory.delete(recursive: true));
    FlutterSecureStorage.setMockInitialValues({});
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/ai_settings.json'),
    );
    const secret = 'sentinel-only-for-secure-storage';
    await service.saveConfig(aiPresets[AiProviderId.gemini]!);
    await service.saveKey(secret);
    expect(await service.isConfigured(), isTrue);
    expect(await const FlutterSecureStorage().read(key: 'ai_api_key'), secret);
    final files = await directory
        .list(recursive: true)
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    expect(files, hasLength(1));
    for (final file in files) {
      expect(await file.readAsString(), isNot(contains(secret)));
    }
    await service.deleteKey();
    expect(await const FlutterSecureStorage().read(key: 'ai_api_key'), isNull);
  });
}
