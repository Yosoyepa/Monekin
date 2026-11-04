import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
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
    FlutterSecureStorage.setMockInitialValues({
      'ai_api_key': 'key-for-url-test',
    });
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/settings.json'),
    );
    await tester.runAsync(
      () => service.saveConfig(
        const AiProviderConfig(
          provider: AiProviderId.custom,
          baseUrl: 'http://ejemplo.com',
          model: 'model-a',
        ),
      ),
    );
    previous = AiService.instance;
    AiService.instance = service;
    await _pumpLoaded(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('ai-save')));
    await tester.tap(find.byKey(const ValueKey('ai-save')));
    await tester.pump();

    expect(find.textContaining('https://'), findsOneWidget);
    expect(await tester.runAsync(service.isConfigured), isFalse);
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
    FlutterSecureStorage.setMockInitialValues({'ai_api_key': savedKey});
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/settings.json'),
    );
    await tester.runAsync(
      () => service.saveConfig(
        AiProviderConfig(
          provider: AiProviderId.custom,
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'model-a',
        ),
      ),
    );
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

Future<void> _pumpLoaded(WidgetTester tester) async {
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
