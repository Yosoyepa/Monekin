import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => aiAllowLocalHttp = kDebugMode);

  test('only https, or http to this device in debug builds, is allowed', () {
    aiAllowLocalHttp = true;
    expect(isAllowedProviderUrl('http://ejemplo.com'), isFalse);
    expect(isAllowedProviderUrl('http://10.0.2.2:8080'), isFalse);
    expect(isAllowedProviderUrl('http://127.0.0.1:9000/v1/'), isTrue);
    expect(isAllowedProviderUrl('http://localhost:8080'), isTrue);
    expect(isAllowedProviderUrl('https://api.deepseek.com'), isTrue);
    expect(isAllowedProviderUrl('ftp://ejemplo.com'), isFalse);
    expect(isAllowedProviderUrl('https://'), isFalse);
    expect(isAllowedProviderUrl(''), isFalse);
  });

  test('in release builds only https is allowed', () {
    aiAllowLocalHttp = false;
    expect(isAllowedProviderUrl('http://localhost:8080'), isFalse);
    expect(isAllowedProviderUrl('http://127.0.0.1:9000/v1/'), isFalse);
    expect(isAllowedProviderUrl('https://localhost:8080'), isTrue);
    expect(isAllowedProviderUrl('https://api.deepseek.com'), isTrue);
  });
  group('AiServiceImpl with a saved provider URL', () {
    late Directory directory;
    late AiServiceImpl service;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ai-url-test');
      FlutterSecureStorage.setMockInitialValues({});
      service = AiServiceImpl(
        configFile: () async => File('${directory.path}/ai_settings.json'),
      );
    });

    tearDown(() => directory.delete(recursive: true));

    Future<void> saveUrl(String url) async {
      final config = AiProviderConfig(
        provider: AiProviderId.custom,
        baseUrl: url,
        model: 'model-a',
      );
      await service.saveConfig(config);
      await service.saveKey('key-for-url-test', config);
    }

    test('a plain http URL to a remote host gets no client', () async {
      await saveUrl('http://ejemplo.com');

      expect(await service.isConfigured(), isFalse);
      await expectLater(
        service.client(),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.notConfigured,
          ),
        ),
      );
      await expectLater(
        service.clientForModels(
          const AiProviderConfig(
            provider: AiProviderId.custom,
            baseUrl: 'http://ejemplo.com',
            model: '',
          ),
        ),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.notConfigured,
          ),
        ),
      );
    });

    test('local http is configured in debug and not in release', () async {
      aiAllowLocalHttp = true;
      await saveUrl('http://localhost:8080');
      expect(await service.isConfigured(), isTrue);

      aiAllowLocalHttp = false;
      expect(await service.isConfigured(), isFalse);
    });
  });
}
