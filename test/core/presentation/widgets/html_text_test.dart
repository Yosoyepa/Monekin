import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/presentation/widgets/html_text.dart';

Future<void> _pumpHtmlText(WidgetTester tester, String htmlString) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HTMLText(
          htmlString: htmlString,
          tags: const {'b': TextStyle(fontWeight: FontWeight.bold)},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders a warning with unbalanced brackets', (tester) async {
    await _pumpHtmlText(tester, '1) blurry total <b>(total</b> tax');

    expect(tester.takeException(), isNull);
    expect(find.textContaining('blurry total'), findsOneWidget);
  });

  testWidgets('does not stall on nested quantifiers in tagged text', (
    tester,
  ) async {
    final stopwatch = Stopwatch()..start();

    await _pumpHtmlText(tester, '<b>(a+)+c</b> <b>${'a' * 30}</b>');

    stopwatch.stop();
    expect(tester.takeException(), isNull);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
