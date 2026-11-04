// R5: the key goes only to its origin; answers are cut at 1 MB before decoding.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/openai_compatible_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late HttpServer server;
  late HttpServer target;
  late OpenAiCompatibleClient client;
  late List<String?> targetAuthorization;

  setUp(() async {
    aiAllowLocalHttp = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    targetAuthorization = [];
    target.listen((request) async {
      targetAuthorization.add(request.headers.value('authorization'));
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{}'},
            },
          ],
          'data': [],
        }),
      );
      await request.response.close();
    });
    client = OpenAiCompatibleClient(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      apiKey: 'fake-key-for-test',
      model: 'm',
    );
  });
  tearDown(() async {
    aiAllowLocalHttp = kDebugMode;
    await server.close(force: true);
    await target.close(force: true);
  });

  for (final status in [301, 302, 303, 307, 308]) {
    test(
      'a $status to another host is not followed and the key stays',
      () async {
        final seen = <String?>[];
        server.listen((request) async {
          seen.add(request.headers.value('authorization'));
          request.response.statusCode = status;
          request.response.headers.set(
            'location',
            'http://localhost:${target.port}/stolen',
          );
          await request.response.close();
        });

        await expectLater(
          client.chat([const AiMessage.user('x')]),
          throwsA(
            isA<AiException>()
                .having((e) => e.kind, 'kind', AiErrorKind.badResponse)
                .having((e) => e.message, 'message', contains('redirect')),
          ),
        );
        await expectLater(client.listModels(), throwsA(isA<AiException>()));

        expect(seen, hasLength(2));
        expect(targetAuthorization, isEmpty);
      },
    );
  }

  test('a body over 1 MB is cut and fails without decoding', () async {
    server.listen((request) async {
      request.response.headers.chunkedTransferEncoding = true;
      for (var i = 0; i < 2; i++) {
        request.response.add(List.filled(1024 * 1024, 0x20));
      }
      try {
        await request.response.close();
      } catch (_) {}
    });

    await expectLater(
      client.listModels(),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.badResponse)
            .having((e) => e.message, 'message', contains('too large')),
      ),
    );
  });

  test('a declared length over 1 MB fails before reading', () async {
    server.listen((request) async {
      request.response.headers.contentLength = 2 * 1024 * 1024;
      request.response.add(List.filled(1024, 0x20));
      await request.response.flush();
      unawaited(request.response.close().catchError((_) => request.response));
    });

    await expectLater(
      client.listModels(),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('large'),
        ),
      ),
    );
  });

  test('plain http is refused in release and sends nothing', () async {
    aiAllowLocalHttp = false;
    var calls = 0;
    server.listen((request) async {
      calls++;
      await request.response.close();
    });

    await expectLater(
      client.chat([const AiMessage.user('x')]),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiErrorKind.notConfigured,
        ),
      ),
    );
    expect(calls, 0);
  });
}
