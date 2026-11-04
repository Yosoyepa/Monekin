import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/openai_compatible_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final keyFile = File(r'D:\Dev\secrets\gemini_test_key.txt');
  final key =
      (Platform.environment['GEMINI_TEST_API_KEY'] ??
              (keyFile.existsSync() ? keyFile.readAsStringSync() : ''))
          .trim();
  test(
    'Gemini lists the model and reads the pharmacy receipt',
    () async {
      final client = OpenAiCompatibleClient(
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
        apiKey: key,
        model: 'gemini-flash-lite-latest',
      );
      final models = await client.listModels();
      expect(models, contains('gemini-flash-lite-latest'));
      final image = await File(
        'test/features_ia/fixtures/receipts/blind3_farmacia.jpg',
      ).readAsBytes();
      final result = await client.chat([
        AiMessage.user(
          'Read this receipt. Return JSON with total as a number and last4 as a four digit string for the payment card.',
          images: [AiImage(bytes: image)],
        ),
      ]);
      final data = result.json();
      expect(data['total'], 67300);
      expect(data['last4'].toString(), '9911');
      // Only the expected receipt fields are printed, never credentials.
      // ignore: avoid_print
      print('model found; total=${data['total']}; last4=${data['last4']}');
    },
    skip: key.isEmpty ? 'Gemini test key unavailable' : false,
  );
}
