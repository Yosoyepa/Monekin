// F-03: the API key belongs to the provider and host it was saved for.
import 'dart:io';

import 'package:flutter/foundation.dart';
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
    test('waits for the user to paste it once to confirm it', () async {
      FlutterSecureStorage.setMockInitialValues({'ai_api_key': 'old-secret'});
      await service.saveConfig(gemini);
      // saveConfig already moved it to the settings that were saved before (the Gemini default).

      expect(await service.hasKey(gemini), isFalse);
      expect(await service.hasKeyToConfirm(gemini), isTrue);
      expect(await service.isConfigured(), isFalse);
      await expectNotConfigured(service.client());
      expect(await service.hasKeyToConfirm(_other), isFalse);
      expect(
        await const FlutterSecureStorage().read(key: 'ai_api_key'),
        isNull,
      );
      expect(
        await const FlutterSecureStorage().read(
          key: AiServiceImpl.keyNameFor(gemini),
        ),
        isNull,
      );

      await service.saveKey('pasted-secret', gemini);

      expect(await service.hasKeyToConfirm(gemini), isFalse);
      expect(await service.hasKey(gemini), isTrue);
      expect(
        (await service.client() as OpenAiCompatibleClient).apiKey,
        'pasted-secret',
      );
    });

    test(
      'is not handed to a destination chosen before the first read',
      () async {
        FlutterSecureStorage.setMockInitialValues({'ai_api_key': 'old-secret'});

        await service.saveConfig(_other);

        expect(await service.isConfigured(), isFalse);
        await expectNotConfigured(service.client());
        expect(await service.hasKeyToConfirm(gemini), isTrue);
        expect(await service.hasKeyToConfirm(_other), isFalse);
      },
    );

    test('deleting the key removes the one to confirm too', () async {
      FlutterSecureStorage.setMockInitialValues({'ai_api_key': 'old-secret'});
      await service.saveConfig(gemini);

      await service.deleteKey(gemini);

      expect(await service.hasKeyToConfirm(gemini), isFalse);
    });
  });

  test('the key identity is the whole origin: scheme, host and port', () async {
    aiAllowLocalHttp = true;
    addTearDown(() => aiAllowLocalHttp = kDebugMode);
    const secure = AiProviderConfig(
      provider: AiProviderId.custom,
      baseUrl: 'https://localhost',
      model: 'm',
    );
    const plain = AiProviderConfig(
      provider: AiProviderId.custom,
      baseUrl: 'http://localhost',
      model: 'm',
    );
    const otherPort = AiProviderConfig(
      provider: AiProviderId.custom,
      baseUrl: 'https://localhost:8443',
      model: 'm',
    );
    await service.saveConfig(secure);
    await service.saveKey('secure-secret', secure);

    expect(await service.hasKey(secure), isTrue);
    expect(await service.hasKey(plain), isFalse);
    expect(await service.hasKey(otherPort), isFalse);
    expect(
      await service.hasKey(
        const AiProviderConfig(
          provider: AiProviderId.custom,
          baseUrl: 'HTTPS://LOCALHOST:443/v1',
          model: 'm',
        ),
      ),
      isTrue,
    );
    await service.saveConfig(plain);
    expect(await service.isConfigured(), isFalse);
    await expectNotConfigured(service.client());
  });
}
