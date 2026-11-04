import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/settings/ai_settings_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

void main() {
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
}

late AiService previous;
