import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:monekin/features_ia/core/ai/ai_client.dart';

final _credentialShapes = RegExp(
  r'\bAIza[0-9A-Za-z_-]{20,}|\bAQ\.[0-9A-Za-z_-]{8,}|\bsk-[0-9A-Za-z_-]{8,}|\b[Bb]earer\s+\S+',
);

/// Hides the saved [apiKey] and credential-shaped text in a provider message.
String _redact(String text, String apiKey) {
  final withoutKey = apiKey.isEmpty
      ? text
      : text.replaceAll(apiKey, '[redacted]');
  return withoutKey.replaceAll(_credentialShapes, '[redacted]');
}

class OpenAiCompatibleClient implements AiClient, AiCappedClient {
  OpenAiCompatibleClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/$path');

  /// Sends one request that never follows redirects, so the key goes only to the saved origin.
  /// The body is read as a stream and cut at [maxAiResponseBytes] before it is decoded.
  Future<String> _request(
    String method,
    Uri uri,
    Duration timeout, {
    String? body,
  }) async {
    if (!isAllowedProviderUrl(baseUrl)) {
      throw const AiException(
        AiErrorKind.notConfigured,
        'The provider URL must use https',
      );
    }
    final client = http.Client();
    try {
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll(_headers);
      if (body != null) request.body = body;
      final response = await (() async {
        final streamed = await client.send(request);
        return (streamed, await _readBounded(streamed));
      })().timeout(timeout);
      final (streamed, text) = response;
      final status = streamed.statusCode;
      if (status >= 200 && status < 300) return text;
      if (status >= 300 && status < 400) {
        throw const AiException(
          AiErrorKind.badResponse,
          'The provider answered with a redirect, which is not followed',
        );
      }
      String message = 'Provider returned HTTP $status';
      try {
        final data = jsonDecode(text);
        if (data is Map &&
            data['error'] is Map &&
            data['error']['message'] is String) {
          message = _redact(data['error']['message'] as String, apiKey);
        }
      } catch (_) {}
      final kind = switch (status) {
        401 || 403 => AiErrorKind.invalidKey,
        429 => AiErrorKind.quotaExceeded,
        _ => AiErrorKind.badResponse,
      };
      throw AiException(kind, message);
    } on TimeoutException {
      throw const AiException(AiErrorKind.timeout, 'Request timed out');
    } on SocketException {
      throw const AiException(AiErrorKind.network, 'Network unavailable');
    } on http.ClientException {
      throw const AiException(AiErrorKind.network, 'Network unavailable');
    } finally {
      client.close();
    }
  }

  /// Reads the body up to [maxAiResponseBytes]; a longer one is dropped without decoding.
  Future<String> _readBounded(http.StreamedResponse response) async {
    const tooLong = AiException(
      AiErrorKind.badResponse,
      'The provider answer is too large',
    );
    final declared = response.contentLength;
    if (declared != null && declared > maxAiResponseBytes) throw tooLong;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxAiResponseBytes) throw tooLong;
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) => chatCapped(
    messages,
    maxTokens: null,
    jsonOutput: jsonOutput,
    timeout: timeout,
  );

  @override
  Future<AiResult> chatCapped(
    List<AiMessage> messages, {
    required int? maxTokens,
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final body = {
      'model': model,
      'temperature': 0.2,
      'max_tokens': ?maxTokens,
      if (jsonOutput) 'response_format': {'type': 'json_object'},
      'messages': messages
          .map(
            (message) => {
              'role': message.role,
              'content': message.images.isEmpty
                  ? message.text
                  : [
                      {'type': 'text', 'text': message.text},
                      for (final image in message.images)
                        {
                          'type': 'image_url',
                          'image_url': {
                            'url':
                                'data:${image.mimeType};base64,${base64Encode(image.bytes)}',
                          },
                        },
                    ],
            },
          )
          .toList(),
    };
    final answer = await _request(
      'POST',
      _uri('chat/completions'),
      timeout,
      body: jsonEncode(body),
    );
    try {
      final data = jsonDecode(answer) as Map<String, dynamic>;
      final text =
          ((data['choices'] as List).first as Map)['message']['content']
              as String;
      final usage = data['usage'] as Map?;
      return AiResult(
        text: text,
        promptTokens: usage?['prompt_tokens'] as int?,
        completionTokens: usage?['completion_tokens'] as int?,
      );
    } catch (_) {
      throw const AiException(AiErrorKind.badResponse, 'Invalid chat response');
    }
  }

  @override
  Future<List<String>> listModels() async {
    final answer = await _request(
      'GET',
      _uri('models'),
      const Duration(seconds: 60),
    );
    try {
      final data = jsonDecode(answer) as Map<String, dynamic>;
      return (data['data'] as List).map((item) {
        final id = (item as Map)['id'] as String;
        return id.startsWith('models/') ? id.substring(7) : id;
      }).toList();
    } catch (_) {
      throw const AiException(
        AiErrorKind.badResponse,
        'Invalid models response',
      );
    }
  }
}
