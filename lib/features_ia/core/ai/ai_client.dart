// Contract for the AI layer of the Finanzas IA fork (T002). Owner: w-ai.
// Every AI call in the app goes through [AiService.instance]. Other features
// must not talk to a provider directly.
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Providers offered in the AI settings. All of them speak the OpenAI
/// compatible `/chat/completions` and `/models` API.
enum AiProviderId {
  /// Google AI Studio, free tier. Base URL
  /// `https://generativelanguage.googleapis.com/v1beta/openai/`.
  gemini,

  /// DeepSeek. Base URL `https://api.deepseek.com`. `deepseek-flash` accepts images.
  deepseek,

  /// OpenRouter. Base URL `https://openrouter.ai/api/v1`.
  openrouter,

  /// Any other OpenAI compatible endpoint (base URL typed by the user).
  custom,
}

class AiProviderConfig {
  const AiProviderConfig({
    required this.provider,
    required this.baseUrl,
    required this.model,
  });

  final AiProviderId provider;
  final String baseUrl;

  /// Model id as returned by the provider's `/models` endpoint.
  final String model;
}

class AiImage {
  const AiImage({required this.bytes, this.mimeType = 'image/jpeg'});

  final Uint8List bytes;
  final String mimeType;
}

class AiMessage {
  const AiMessage.system(this.text) : role = 'system', images = const [];
  const AiMessage.user(this.text, {this.images = const []}) : role = 'user';

  final String role;
  final String text;
  final List<AiImage> images;
}

/// Longest model answer [AiResult.json] parses (256 KB of text).
const maxAiResponseChars = 256 * 1024;

/// Most bytes read from a provider answer; the rest of the body is dropped before decoding.
const maxAiResponseBytes = 1024 * 1024;

const _localHosts = {'localhost', '127.0.0.1'};

/// Whether plain http to this device is allowed. Only debug builds; tests switch it.
bool aiAllowLocalHttp = kDebugMode;

/// The API key may only travel to https, or (debug builds only) to http on this device.
bool isAllowedProviderUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  return uri.scheme == 'https' ||
      (aiAllowLocalHttp &&
          uri.scheme == 'http' &&
          _localHosts.contains(uri.host.toLowerCase()));
}

class AiResult {
  const AiResult({
    required this.text,
    this.promptTokens,
    this.completionTokens,
  });

  final String text;
  final int? promptTokens;
  final int? completionTokens;

  /// Parses [text] as one JSON object. Tolerates a ```json fenced block.
  /// Throws [AiException] with [AiErrorKind.badResponse] when it is not JSON
  /// or longer than [maxAiResponseChars].
  Map<String, dynamic> json() {
    if (text.length > maxAiResponseChars) {
      throw const AiException(AiErrorKind.badResponse, 'Response too long');
    }
    var raw = text.trim();
    if (raw.length >= 6 && raw.startsWith('```') && raw.endsWith('```')) {
      raw = raw.substring(3, raw.length - 3);
      if (raw.startsWith('json')) raw = raw.substring(4);
      raw = raw.trim();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const AiException(
      AiErrorKind.badResponse,
      'The model did not answer a JSON object',
    );
  }
}

enum AiErrorKind {
  notConfigured,
  invalidKey,
  quotaExceeded,
  network,
  timeout,
  badResponse,
  unknown,
}

class AiException implements Exception {
  const AiException(this.kind, this.message);

  final AiErrorKind kind;
  final String message;

  @override
  String toString() => 'AiException($kind): $message';
}

abstract class AiClient {
  /// Sends one chat completion. When [jsonOutput] is true the request asks for
  /// a single JSON object (`response_format: {type: json_object}`).
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  });

  /// Model ids offered by the configured provider.
  Future<List<String>> listModels();
}

/// A client that can ask the provider to stop the answer at a number of tokens (`max_tokens`).
abstract interface class AiCappedClient {
  Future<AiResult> chatCapped(
    List<AiMessage> messages, {
    required int maxTokens,
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  });
}

extension AiClientCap on AiClient {
  /// [AiClient.chat] with a token cap for the answer. A client that cannot cap (a test fake) answers uncapped.
  Future<AiResult> chatWithCap(
    List<AiMessage> messages, {
    required int maxTokens,
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return switch (this) {
      final AiCappedClient capped => capped.chatCapped(
        messages,
        maxTokens: maxTokens,
        jsonOutput: jsonOutput,
        timeout: timeout,
      ),
      _ => chat(messages, jsonOutput: jsonOutput, timeout: timeout),
    };
  }
}

/// `max_tokens` per action: a wide margin over what the fixtures use today.
abstract final class AiTokenCaps {
  static const receipt = 1024;
  static const statement = 16384;
  static const categorize = 4096;
  static const recategorize = 4096;
  static const insights = 1024;
  static const notice = 512;
}

abstract class AiService {
  /// Replaced at startup by `initFeaturesIa()` with the real implementation.
  static AiService instance = _NotReadyAiService();

  /// Tests of other features inject a fake client here.
  static AiClient? debugClientOverride;

  /// True when a provider, a model and an API key are saved.
  Future<bool> isConfigured();

  /// The client for the saved settings. Throws [AiException] with
  /// [AiErrorKind.notConfigured] when [isConfigured] is false.
  Future<AiClient> client();
}

class _NotReadyAiService implements AiService {
  @override
  Future<bool> isConfigured() async => AiService.debugClientOverride != null;

  @override
  Future<AiClient> client() async {
    final fake = AiService.debugClientOverride;
    if (fake != null) return fake;
    throw const AiException(AiErrorKind.notConfigured, 'AI is not configured');
  }
}
