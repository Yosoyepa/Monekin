// Tests that call a real AI provider run only on request: RUN_REAL_AI_TESTS=1 and a Gemini test key.
// The key is read from GEMINI_TEST_API_KEY or D:\Dev\secrets\gemini_test_key.txt and is never printed.
import 'dart:io';

/// The Gemini test key, or null when there is none.
String? geminiTestKey() {
  final env = Platform.environment['GEMINI_TEST_API_KEY']?.trim();
  if (env != null && env.isNotEmpty) return env;
  final file = File(r'D:\Dev\secrets\gemini_test_key.txt');
  if (!file.existsSync()) return null;
  final key = file.readAsStringSync().trim();
  return key.isEmpty ? null : key;
}

/// `skip:` value for a test that calls the real AI: a reason, or false when it should run.
Object realAiSkip() {
  if (Platform.environment['RUN_REAL_AI_TESTS'] != '1') {
    return 'Real AI tests run only with RUN_REAL_AI_TESTS=1';
  }
  return geminiTestKey() == null ? 'No Gemini test key' : false;
}
