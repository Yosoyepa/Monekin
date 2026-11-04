// Test support for the consent of the AI functions (T002, round 3).
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';

/// Replaces the consent of the app by one kept in memory and restores it when the test ends.
/// With [grantAll] every AI function is already allowed for the destination in use (the Gemini preset when the
/// real AI service is not installed); without it nothing is, as on a first launch.
Future<AiConsent> useTestConsent({bool grantAll = true}) async {
  final previous = AiConsent.instance;
  final consent = AiConsent.inMemory();
  AiConsent.instance = consent;
  addTearDown(() => AiConsent.instance = previous);
  if (grantAll) {
    final config = await currentAiConfig();
    for (final feature in AiFeature.values) {
      await consent.grant(feature, config);
    }
  }
  return consent;
}

/// A fake client that records every request and answers [answer] (or throws it when it is an exception).
class RecordingAiClient implements AiClient {
  RecordingAiClient([this.answer = '{}']);

  Object answer;
  final requests = <List<AiMessage>>[];

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    requests.add(messages);
    final reply = answer;
    if (reply is Exception) throw reply;
    return AiResult(text: reply as String);
  }

  @override
  Future<List<String>> listModels() async => const [];
}
