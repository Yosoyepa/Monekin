import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'only https, or http to localhost, 127.0.0.1 and 10.0.2.2, is allowed',
    () {
      expect(isAllowedProviderUrl('http://ejemplo.com'), isFalse);
      expect(isAllowedProviderUrl('http://10.0.2.2:8080'), isTrue);
      expect(isAllowedProviderUrl('http://127.0.0.1:9000/v1/'), isTrue);
      expect(isAllowedProviderUrl('http://localhost:8080'), isTrue);
      expect(isAllowedProviderUrl('https://api.deepseek.com'), isTrue);
      expect(isAllowedProviderUrl('ftp://ejemplo.com'), isFalse);
      expect(isAllowedProviderUrl('https://'), isFalse);
      expect(isAllowedProviderUrl(''), isFalse);
    },
  );

  group('AiServiceImpl with a saved provider URL', () {
    late Directory directory;
    late AiServiceImpl service;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ai-url-test');
      FlutterSecureStorage.setMockInitialValues({
        'ai_api_key': 'key-for-url-test',
      });
      service = AiServiceImpl(
        configFile: () async => File('${directory.path}/ai_settings.json'),
      );
    });

    tearDown(() => directory.delete(recursive: true));

    Future<void> saveUrl(String url) => service.saveConfig(
      AiProviderConfig(
        provider: AiProviderId.custom,
        baseUrl: url,
        model: 'model-a',
      ),
    );

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

    test('the emulator address is configured with the saved key', () async {
      await saveUrl('http://10.0.2.2:8080');

      expect(await service.isConfigured(), isTrue);
    });
  });
}
