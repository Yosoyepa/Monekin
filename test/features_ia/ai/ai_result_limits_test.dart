// F-02: the model answer is capped before parsing and the fence is stripped without a regex.
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';

AiException _badResponse(AiResult result) {
  try {
    result.json();
  } on AiException catch (e) {
    return e;
  }
  fail('json() did not throw');
}

void main() {
  group('whitespace-heavy answers', () {
    for (final size in [2000, 200 * 1024]) {
      test('$size-char answer with an unclosed fence is rejected fast', () {
        final watch = Stopwatch()..start();
        final error = _badResponse(AiResult(text: '```${' ' * size}x'));
        watch.stop();
        // ignore: avoid_print
        print(
          'whitespace answer of $size chars: ${watch.elapsedMilliseconds} ms',
        );
        expect(error.kind, AiErrorKind.badResponse);
        expect(watch.elapsedMilliseconds, lessThan(50));
      });
    }

    test('100 KB of whitespace around a closed fence is processed fast', () {
      final watch = Stopwatch()..start();
      final json = AiResult(
        text: '```json${' ' * 100000}{"ok":true}${' ' * 100000}```',
      ).json();
      watch.stop();
      expect(json, {'ok': true});
      expect(watch.elapsedMilliseconds, lessThan(50));
    });
  });

  test('an answer over 256 KB is rejected as too long', () {
    final error = _badResponse(
      AiResult(text: '{"a":"${'x' * maxAiResponseChars}"}'),
    );
    expect(error.kind, AiErrorKind.badResponse);
    expect(error.message, 'Response too long');
  });

  test('an answer of exactly 256 KB still parses', () {
    const prefix = '{"a":"';
    const suffix = '"}';
    final body =
        prefix +
        'x' * (maxAiResponseChars - prefix.length - suffix.length) +
        suffix;
    expect(body.length, maxAiResponseChars);
    expect(AiResult(text: body).json()['a'], hasLength(body.length - 8));
  });

  group('fenced answers', () {
    test('plain, json-tagged and padded fences', () {
      expect(AiResult(text: '{"a":1}').json(), {'a': 1});
      expect(AiResult(text: '```json\n{"a":1}\n```').json(), {'a': 1});
      expect(AiResult(text: '  ```\n{"a":1}\n```  ').json(), {'a': 1});
      expect(AiResult(text: '```json{"a":1}```').json(), {'a': 1});
    });

    test('malformed fences are not JSON', () {
      for (final text in [
        '```',
        '``````',
        '```json',
        '```{"a":1}',
        '{"a":1}```',
      ]) {
        expect(
          _badResponse(AiResult(text: text)).kind,
          AiErrorKind.badResponse,
          reason: text,
        );
      }
    });

    test('an array is not an object', () {
      expect(
        _badResponse(const AiResult(text: '[1]')).kind,
        AiErrorKind.badResponse,
      );
    });
  });
}
