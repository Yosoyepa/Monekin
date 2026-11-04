// Chanchi leaves the tree before its layers are preloaded: no controller is created while it is being disposed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';

void main() {
  testWidgets('unmounting before the preload finishes raises nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChanchiMascot(mood: ChanchiMood.happy, size: 120),
      ),
    );
    // The layers are still loading: the mascot shows an empty box.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(ChanchiMascot.preload);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
