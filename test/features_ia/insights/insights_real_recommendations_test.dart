// Live check of the recommendation prompt against Gemini (T002). Skipped unless a test key is available.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_prompt.dart';

const _endpoint =
    'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
const _model = 'gemini-flash-lite-latest';

/// Minimal OpenAI-compatible client for this test only. The app's client is implemented in core/ai.
class _GeminiTestClient implements AiClient {
  _GeminiTestClient(this._apiKey);

  final String _apiKey;

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final http = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await http.postUrl(Uri.parse(_endpoint)).timeout(timeout);
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
      request.write(
        jsonEncode({
          'model': _model,
          'messages': [
            for (final m in messages) {'role': m.role, 'content': m.text},
          ],
          if (jsonOutput) 'response_format': {'type': 'json_object'},
        }),
      );

      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw AiException(AiErrorKind.unknown, 'HTTP ${response.statusCode}');
      }

      final choices =
          (jsonDecode(body) as Map<String, dynamic>)['choices'] as List;
      final message =
          (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>;
      return AiResult(text: message['content'] as String);
    } finally {
      http.close(force: true);
    }
  }

  @override
  Future<List<String>> listModels() async => const [];
}

/// Key from the environment or from the local secrets file. It is never printed or copied into the repo.
String? _testKey() {
  final fromEnv = Platform.environment['GEMINI_TEST_API_KEY']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

  final file = File(r'D:\Dev\secrets\gemini_test_key.txt');
  if (!file.existsSync()) return null;
  final key = file.readAsStringSync().trim();
  return key.isEmpty ? null : key;
}

InsightTransaction _tx(
  String title,
  double amount,
  DateTime date,
  String categoryId,
  String categoryName,
) => InsightTransaction(
  title: title,
  amount: amount,
  date: date,
  categoryId: categoryId,
  categoryName: categoryName,
);

void main() {
  final key = _testKey();

  test(
    'recommendations for example aggregates come back as three tips',
    () async {
      final aggregates = computeInsightsAggregates(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 11, 1),
        transactions: [
          _tx('Supermercado', 300000, DateTime(2026, 9, 14), 'food', 'Comida'),
          _tx('Streaming', 35000, DateTime(2026, 9, 28), 'leisure', 'Ocio'),
          _tx('Taxi', 20000, DateTime(2026, 9, 2), 'transport', 'Transporte'),
          _tx('Supermercado', 420000, DateTime(2026, 10, 3), 'food', 'Comida'),
          _tx('Restaurante', 180000, DateTime(2026, 10, 12), 'food', 'Comida'),
          _tx(
            'Gasolina',
            150000,
            DateTime(2026, 10, 15),
            'transport',
            'Transporte',
          ),
          _tx('Taxi', 25000, DateTime(2026, 10, 5), 'transport', 'Transporte'),
          _tx('Streaming', 35000, DateTime(2026, 10, 28), 'leisure', 'Ocio'),
          _tx('Cine', 30000, DateTime(2026, 10, 9), 'leisure', 'Ocio'),
          _tx('Concierto', 400000, DateTime(2026, 10, 25), 'leisure', 'Ocio'),
        ],
      );
      final messages = buildRecommendationMessages(
        aggregates,
        currency: 'COP',
        language: 'Spanish',
      );

      final result = await _GeminiTestClient(key!).chat(messages);
      final tips = result.json()['tips'];

      // ignore: avoid_print
      print('Respuesta real de $_model: ${jsonEncode(tips)}');
      expect(tips, isA<List<dynamic>>());
      expect(tips as List<dynamic>, hasLength(3));
      for (final tip in tips) {
        expect(tip, isA<String>());
        expect((tip as String).trim(), isNotEmpty);
      }
    },
    skip: key == null
        ? r'no Gemini test key (GEMINI_TEST_API_KEY or D:\Dev\secrets\gemini_test_key.txt)'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
