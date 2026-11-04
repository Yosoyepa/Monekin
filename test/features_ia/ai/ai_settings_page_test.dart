import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/settings/ai_settings_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  testWidgets('saving and deleting a key changes configuration', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('ai-settings-test');
    addTearDown(() {
      AiService.instance = previous;
      directory.deleteSync(recursive: true);
    });
    FlutterSecureStorage.setMockInitialValues({});
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/settings.json'),
    );
    previous = AiService.instance;
    AiService.instance = service;
    _tallScreen(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        TranslationProvider(child: const MaterialApp(home: AiSettingsPage())),
      );
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byKey(const ValueKey('ai-key')).evaluate().isNotEmpty) return;
      }
      fail('Settings did not load');
    });
    expect(await tester.runAsync(service.isConfigured), isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('ai-key')),
      'a-test-only-secret',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('ai-save')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('ai-save')));
      for (var i = 0; i < 100; i++) {
        if (await service.isConfigured()) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      fail('Key was not saved');
    });
    await tester.pumpAndSettle();
    expect(await tester.runAsync(service.isConfigured), isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('ai-delete')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('ai-delete')));
      for (var i = 0; i < 100; i++) {
        if (!await service.isConfigured()) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      fail('Key was not deleted');
    });
    await tester.pumpAndSettle();
    expect(await tester.runAsync(service.isConfigured), isFalse);
  });

  testWidgets('a provider URL over plain http is not saved', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'ai-settings-url-test',
    );
    addTearDown(() {
      AiService.instance = previous;
      directory.deleteSync(recursive: true);
    });
    FlutterSecureStorage.setMockInitialValues({});
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/settings.json'),
    );
    const insecure = AiProviderConfig(
      provider: AiProviderId.custom,
      baseUrl: 'http://ejemplo.com',
      model: 'model-a',
    );
    await tester.runAsync(() async {
      await service.saveConfig(insecure);
      await service.saveKey('key-for-url-test', insecure);
    });
    previous = AiService.instance;
    AiService.instance = service;
    await _pumpLoaded(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('ai-save')));
    await tester.tap(find.byKey(const ValueKey('ai-save')));
    await tester.pump();

    expect(find.textContaining('https://'), findsOneWidget);
    expect(await tester.runAsync(service.isConfigured), isFalse);
  });

  testWidgets('switching to Custom asks for the key again and sends none', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('ai-settings-bind');
    addTearDown(() {
      AiService.instance = previous;
      directory.deleteSync(recursive: true);
    });
    FlutterSecureStorage.setMockInitialValues({});
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/settings.json'),
    );
    final gemini = aiPresets[AiProviderId.gemini]!;
    await tester.runAsync(() async {
      await service.saveConfig(gemini);
      await service.saveKey('gemini-secret', gemini);
    });
    previous = AiService.instance;
    AiService.instance = service;
    await _pumpLoaded(tester);
    final strings = Translations.of(
      tester.element(find.byType(AiSettingsPage)),
    );
    expect(find.text(strings.ia_settings.key_saved), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('ai-provider-custom')),
    );
    await tester.tap(find.byKey(const ValueKey('ai-provider-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-url')),
      'https://otro.example',
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.text(strings.ia_settings.key_saved), findsNothing);
    expect(find.text(strings.ia_settings.key_per_destination), findsOneWidget);
    expect(await tester.runAsync(() => service.hasKey(gemini)), isTrue);
    expect(
      await tester.runAsync(
        () => service.hasKey(
          const AiProviderConfig(
            provider: AiProviderId.custom,
            baseUrl: 'https://otro.example',
            model: '',
          ),
        ),
      ),
      isFalse,
    );
  });

  testWidgets('turning a function off in the settings makes it ask again', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'ai-settings-consent',
    );
    addTearDown(() {
      AiService.instance = previous;
      AiConsent.instance = previousConsent;
      directory.deleteSync(recursive: true);
    });
    FlutterSecureStorage.setMockInitialValues({});
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/settings.json'),
    );
    final gemini = aiPresets[AiProviderId.gemini]!;
    previousConsent = AiConsent.instance;
    final consent = AiConsent.inMemory();
    AiConsent.instance = consent;
    for (final feature in [AiFeature.receipt, AiFeature.statement]) {
      await consent.grant(feature, gemini);
    }
    previous = AiService.instance;
    AiService.instance = service;
    await _pumpLoaded(tester);

    SwitchListTile tile(AiFeature feature) =>
        tester.widget(find.byKey(ValueKey('ai-consent-${feature.name}')));
    expect(tile(AiFeature.receipt).value, isTrue);
    expect(tile(AiFeature.notice).value, isFalse);

    final receipt = find.byKey(const ValueKey('ai-consent-receipt'));
    await tester.ensureVisible(receipt);
    await tester.runAsync(() async {
      await tester.tap(receipt);
      for (var i = 0; i < 100; i++) {
        if (!await consent.isGranted(AiFeature.receipt, gemini)) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      fail('The consent was not revoked');
    });
    await tester.pumpAndSettle();

    expect(tile(AiFeature.receipt).value, isFalse);
    expect(tile(AiFeature.statement).value, isTrue);
    expect(await consent.isGranted(AiFeature.receipt, gemini), isFalse);
    expect(await consent.isGranted(AiFeature.statement, gemini), isTrue);
  });

  testWidgets('a key moved from an older version is shown as to confirm', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'ai-settings-confirm',
    );
    addTearDown(() {
      AiService.instance = previous;
      directory.deleteSync(recursive: true);
    });
    FlutterSecureStorage.setMockInitialValues({'ai_api_key': 'old-key'});
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/settings.json'),
    );
    previous = AiService.instance;
    AiService.instance = service;
    await _pumpLoaded(tester);

    final strings = Translations.of(
      tester.element(find.byType(AiSettingsPage)),
    );
    expect(find.text(strings.ia_settings.key_to_confirm), findsOneWidget);
  });

  testWidgets('a 429 message that repeats the key does not show the key', (
    tester,
  ) async {
    const savedKey = 'key-429-sentinel';
    final directory = Directory.systemTemp.createTempSync(
      'ai-settings-429-test',
    );
    late HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 429;
        request.response.write(
          jsonEncode({
            'error': {
              'message':
                  'Quota exceeded for $savedKey, retry with Bearer $savedKey',
            },
          }),
        );
        await request.response.close();
      });
    });
    addTearDown(() {
      AiService.instance = previous;
      unawaited(server.close(force: true));
      directory.deleteSync(recursive: true);
    });
    FlutterSecureStorage.setMockInitialValues({});
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/settings.json'),
    );
    final local = AiProviderConfig(
      provider: AiProviderId.custom,
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'model-a',
    );
    await tester.runAsync(() async {
      await service.saveConfig(local);
      await service.saveKey(savedKey, local);
    });
    previous = AiService.instance;
    AiService.instance = service;
    await _pumpLoaded(tester);

    await tester.ensureVisible(find.byType(OutlinedButton));
    await tester.runAsync(() async {
      await tester.tap(find.byType(OutlinedButton));
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.textContaining('[redacted]').evaluate().isNotEmpty) return;
      }
      fail('The provider error was not shown');
    });

    expect(find.textContaining(savedKey), findsNothing);
  });
}

late AiService previous;
late AiConsent previousConsent;

/// A tall screen, so every field of the settings is built without scrolling.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpLoaded(WidgetTester tester) async {
  _tallScreen(tester);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      TranslationProvider(child: const MaterialApp(home: AiSettingsPage())),
    );
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      if (find.byKey(const ValueKey('ai-key')).evaluate().isNotEmpty) return;
    }
    fail('Settings did not load');
  });
}
