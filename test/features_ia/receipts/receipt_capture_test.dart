// A photo that is not a JPEG or PNG and cannot be converted ends with a clear message, not with an error.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/receipts/receipt_capture.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../utils/consent_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an unsupported photo shows err_unsupported_image', (
    tester,
  ) async {
    await useTestConsent();
    final client = RecordingAiClient();
    AiService.debugClientOverride = client;
    final dir = Directory.systemTemp.createTempSync('receipt_capture_test');
    final notAnImage = File('${dir.path}/notes.txt')
      ..writeAsBytesSync(ascii.encode('not an image at all'));
    debugReceiptPhotosOverride = () async => [XFile(notAnImage.path)];
    addTearDown(() {
      AiService.debugClientOverride = null;
      debugReceiptPhotosOverride = null;
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('capture'),
                onPressed: () => startReceiptCapture(context),
                child: const Text('capture'),
              ),
            ),
          ),
        ),
      ),
    );

    final t = Translations.of(tester.element(find.byKey(const Key('capture'))));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('capture')));
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find
            .text(t.ia_receipts.err_unsupported_image)
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
      fail('The message was not shown');
    });

    expect(client.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
