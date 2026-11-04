import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/openai_compatible_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late HttpServer server;
  late OpenAiCompatibleClient client;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = OpenAiCompatibleClient(
      baseUrl: 'http://127.0.0.1:${server.port}/v1/',
      apiKey: 'test-secret',
      model: 'model-a',
    );
  });
  tearDown(() async => server.close(force: true));

  test('sends image, authorization and JSON format', () async {
    final received = Completer<void>();
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/chat/completions');
      expect(request.headers.value('authorization'), 'Bearer test-secret');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body['model'], 'model-a');
      expect(body['temperature'], 0.2);
      expect(body['response_format'], {'type': 'json_object'});
      expect(body['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'read'},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,AQID'},
            },
          ],
        },
      ]);
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{"ok":true}'},
            },
          ],
          'usage': {'prompt_tokens': 2, 'completion_tokens': 3},
        }),
      );
      await request.response.close();
      received.complete();
    });
    final result = await client.chat([
      AiMessage.user(
        'read',
        images: [
          AiImage(bytes: Uint8List.fromList([1, 2, 3])),
        ],
      ),
    ]);
    expect(result.json(), {'ok': true});
    expect(result.promptTokens, 2);
    await received.future;
  });

  test('lists model IDs with and without Gemini prefix', () async {
    server.listen((request) async {
      expect(request.uri.path, '/v1/models');
      request.response.write(
        jsonEncode({
          'data': [
            {'id': 'models/gemini'},
            {'id': 'other'},
          ],
        }),
      );
      await request.response.close();
    });
    expect(await client.listModels(), ['gemini', 'other']);
  });

  for (final entry in {
    401: AiErrorKind.invalidKey,
    403: AiErrorKind.invalidKey,
    429: AiErrorKind.quotaExceeded,
    500: AiErrorKind.badResponse,
  }.entries) {
    test('HTTP ${entry.key} maps to ${entry.value}', () async {
      server.listen((request) async {
        request.response.statusCode = entry.key;
        request.response.write(
          jsonEncode({
            'error': {'message': 'provider detail'},
          }),
        );
        await request.response.close();
      });
      await expectLater(
        client.listModels(),
        throwsA(
          isA<AiException>()
              .having((e) => e.kind, 'kind', entry.value)
              .having((e) => e.message, 'message', 'provider detail'),
        ),
      );
    });
  }

  test('malformed response maps to badResponse', () async {
    server.listen((request) async {
      request.response.write('{}');
      await request.response.close();
    });
    await expectLater(
      client.listModels(),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiErrorKind.badResponse,
        ),
      ),
    );
  });

  test('timeout maps to timeout', () async {
    server.listen((request) {});
    await expectLater(
      client.chat([
        const AiMessage.user('x'),
      ], timeout: const Duration(milliseconds: 30)),
      throwsA(
        isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.timeout),
      ),
    );
  });

  test('connection failure maps to network', () async {
    final port = server.port;
    await server.close(force: true);
    client = OpenAiCompatibleClient(
      baseUrl: 'http://127.0.0.1:$port',
      apiKey: 'key',
      model: 'model',
    );
    await expectLater(
      client.listModels(),
      throwsA(
        isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.network),
      ),
    );
  });
}
