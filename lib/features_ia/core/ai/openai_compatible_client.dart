import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class OpenAiCompatibleClient implements AiClient {
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

  Future<http.Response> _request(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    try {
      final response = await request().timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      String message = 'Provider returned HTTP ${response.statusCode}';
      try {
        final data = jsonDecode(response.body);
        if (data is Map &&
            data['error'] is Map &&
            data['error']['message'] is String) {
          message = _redact(data['error']['message'] as String, apiKey);
        }
      } catch (_) {}
      final kind = switch (response.statusCode) {
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
    }
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
  }) async {
    final body = {
      'model': model,
      'temperature': 0.2,
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
    final response = await _request(
      () => http.post(
        _uri('chat/completions'),
        headers: _headers,
        body: jsonEncode(body),
      ),
      timeout,
    );
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
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
    final response = await _request(
      () => http.get(_uri('models'), headers: _headers),
      const Duration(seconds: 60),
    );
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
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
