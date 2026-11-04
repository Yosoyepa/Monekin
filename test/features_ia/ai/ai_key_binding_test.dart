// F-03: the API key belongs to the provider and host it was saved for.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/core/ai/openai_compatible_client.dart';

const _other = AiProviderConfig(
  provider: AiProviderId.custom,
  baseUrl: 'https://otro.example',
  model: 'model-b',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late AiServiceImpl service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-key-binding');
    FlutterSecureStorage.setMockInitialValues({});
    service = AiServiceImpl(
      configFile: () async => File('${directory.path}/ai_settings.json'),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  Future<void> expectNotConfigured(Future<AiClient> client) => expectLater(
    client,
    throwsA(
      isA<AiException>().having(
        (e) => e.kind,
        'kind',
        AiErrorKind.notConfigured,
      ),
    ),
  );

  const gemini = AiProviderConfig(
    provider: AiProviderId.gemini,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
    model: 'gemini-flash-lite-latest',
  );

  test(
    'a Gemini key is not sent to Custom https://otro.example and is back on Gemini',
    () async {
      await service.saveConfig(gemini);
      await service.saveKey('gemini-secret', gemini);
      final first = await service.client() as OpenAiCompatibleClient;
      expect(first.apiKey, 'gemini-secret');

      await service.saveConfig(_other);

      expect(await service.isConfigured(), isFalse);
      await expectNotConfigured(service.client());
      await expectNotConfigured(service.clientForModels(_other));
      expect(await service.hasKey(_other), isFalse);

      await service.saveConfig(gemini);

      expect(await service.hasKey(gemini), isTrue);
      final back = await service.client() as OpenAiCompatibleClient;
      expect(back.apiKey, 'gemini-secret');
      expect(back.baseUrl, gemini.baseUrl);
    },
  );

  test(
    'a key is bound to the host: another host of the same provider gets none',
    () async {
      const first = AiProviderConfig(
        provider: AiProviderId.custom,
        baseUrl: 'https://uno.example/v1',
        model: 'm',
      );
      const second = AiProviderConfig(
        provider: AiProviderId.custom,
        baseUrl: 'https://dos.example/v1',
        model: 'm',
      );
      await service.saveConfig(first);
      await service.saveKey('uno-secret', first);

      expect(await service.hasKey(first), isTrue);
      expect(await service.hasKey(second), isFalse);
      await service.saveConfig(second);
      await expectNotConfigured(service.client());
      await service.saveConfig(
        const AiProviderConfig(
          provider: AiProviderId.custom,
          baseUrl: 'https://UNO.example/other/path',
          model: 'm',
        ),
      );
      expect(
        (await service.client() as OpenAiCompatibleClient).apiKey,
        'uno-secret',
      );
    },
  );

  test(
    'keys of two destinations live side by side and delete one by one',
    () async {
      await service.saveConfig(gemini);
      await service.saveKey('gemini-secret', gemini);
      await service.saveKey('other-secret', _other);

      await service.deleteKey(_other);

      expect(await service.hasKey(_other), isFalse);
      expect(await service.hasKey(gemini), isTrue);
    },
  );

  group('key saved before keys were per destination', () {
    test('moves to the provider and host saved at the first read', () async {
      FlutterSecureStorage.setMockInitialValues({'ai_api_key': 'old-secret'});
      await service.saveConfig(gemini);
      // saveConfig already moved it to the settings that were saved before (the Gemini default).

      expect(await service.hasKey(gemini), isTrue);
      expect(await service.hasKey(_other), isFalse);
      expect(
        await const FlutterSecureStorage().read(key: 'ai_api_key'),
        isNull,
      );
      expect(
        await const FlutterSecureStorage().read(
          key: AiServiceImpl.keyNameFor(gemini),
        ),
        'old-secret',
      );
    });

    test(
      'is not handed to a destination chosen before the first read',
      () async {
        FlutterSecureStorage.setMockInitialValues({'ai_api_key': 'old-secret'});

        await service.saveConfig(_other);

        expect(await service.isConfigured(), isFalse);
        await expectNotConfigured(service.client());
        expect(await service.hasKey(gemini), isTrue);
      },
    );
  });
}
