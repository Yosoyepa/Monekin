import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';

import 'brand_test_utils.dart';

Widget _app(Widget child, {required bool reduce}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: Scaffold(body: Center(child: child)),
  ),
);

String _fmt(double v) => v.toStringAsFixed(2);

void main() {
  group('CountUpText', () {
    testWidgets('shows the final value on the first frame when reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(CountUpText(value: 1250, format: _fmt), reduce: true),
      );

      expect(find.text('1250.00'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('counts up over 700 ms otherwise', (tester) async {
      await tester.pumpWidget(
        _app(CountUpText(value: 1250, format: _fmt), reduce: false),
      );

      expect(find.text('1250.00'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('1250.00'), findsOneWidget);
    });

    testWidgets('uses tabular figures', (tester) async {
      await tester.pumpWidget(
        _app(CountUpText(value: 1, format: _fmt), reduce: true),
      );

      final text = tester.widget<Text>(find.text('1.00'));
      expect(text.style!.fontFeatures, tabularFigures);
    });
  });

  group('BrandMotion', () {
    testWidgets('reduces durations to zero or 150 ms', (tester) async {
      late BrandMotion motion;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              motion = BrandMotion.of(context);
              return const SizedBox();
            },
          ),
          reduce: true,
        ),
      );

      expect(motion.tap, Duration.zero);
      expect(motion.stagger, Duration.zero);
      for (final d in [motion.state, motion.card, motion.page]) {
        expect(d, lessThanOrEqualTo(const Duration(milliseconds: 150)));
      }
    });
  });

  group('StaggeredEntrance', () {
    testWidgets('does not animate when reduced', (tester) async {
      await tester.pumpWidget(
        _app(
          const StaggeredEntrance(index: 3, child: Text('row')),
          reduce: true,
        ),
      );

      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.widget<Text>(find.text('row')), isNotNull);
    });

    testWidgets('only the first 8 items animate', (tester) async {
      await tester.pumpWidget(
        _app(
          const StaggeredEntrance(index: 8, child: Text('row')),
          reduce: false,
        ),
      );

      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('ChanchiMascot', () {
    testWidgets('schedules no hop, blink or extras when reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ChanchiMascot(mood: ChanchiMood.happy, animate: true),
          reduce: true,
        ),
      );
      await settleSvgs(tester);

      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Unmounting would fail the test on a pending blink timer.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('hops and blinks when motion is allowed', (tester) async {
      await tester.pumpWidget(
        _app(
          const ChanchiMascot(mood: ChanchiMood.happy, animate: true),
          reduce: false,
        ),
      );
      await settleSvgs(tester);

      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is excluded from semantics', (tester) async {
      await tester.pumpWidget(
        _app(
          const ChanchiMascot(mood: ChanchiMood.idle, animate: false),
          reduce: false,
        ),
      );
      await settleSvgs(tester);

      expect(
        find.descendant(
          of: find.byType(ChanchiMascot),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
    });
  });
}
