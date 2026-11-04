// The consent pins provider, origin and model: the approved request goes to that destination and to no other.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';

import '../utils/consent_support.dart';

const _first = AiProviderConfig(
  provider: AiProviderId.gemini,
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  model: 'model-one',
);
const _second = AiProviderConfig(
  provider: AiProviderId.gemini,
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  model: 'model-two',
);

const _catalog = AiCatalog(
  accounts: [CatalogAccount(id: 'acc-1', name: 'Cuenta', currency: 'COP')],
  categories: [CatalogCategory(id: 'cat-food', name: 'Food', type: 'E')],
);

void main() {
  late Directory directory;
  late AiServiceImpl service;
  late AiService previous;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('ai_destination_pin');
    FlutterSecureStorage.setMockInitialValues({});
    service = AiServiceImpl(
      configFile: () async => File('${directory.path}/ai_settings.json'),
    );
    previous = AiService.instance;
    AiService.instance = service;
    await service.saveConfig(_first);
    await service.saveKey('fake-key-for-tests');
    final consent = await useTestConsent(grantAll: false);
    await consent.grant(AiFeature.statement, _first);
  });

  tearDown(() {
    AiService.instance = previous;
    directory.deleteSync(recursive: true);
  });

  test('a client is made for the destination that was allowed', () async {
    final client = await aiClientFor(AiFeature.statement) as GuardedAiClient;

    expect(aiDestinationOf(client.config), aiDestinationOf(_first));
  });

  test(
    'changing the model asks again: no client until it is allowed',
    () async {
      await service.saveConfig(_second);

      await expectLater(
        aiClientFor(AiFeature.statement),
        throwsA(isA<AiException>()),
      );
    },
  );

  test('a statement approved for one model is not sent to another', () async {
    final importer = StatementImporter(catalogLoader: () async => _catalog);
    final send = await importer.prepareRead('01/11/2026 EXITO -45.900');
    expect(aiDestinationOf(send.config), aiDestinationOf(_first));

    // The user changes the model and allows it, after the preview and before the send.
    await service.saveConfig(_second);
    await AiConsent.instance.grant(AiFeature.statement, _second);

    await expectLater(
      importer.parseWithAi('01/11/2026 EXITO -45.900', 'acc-1', send: send),
      throwsA(isA<StatementApprovalChanged>()),
    );
  });
}
