import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/features_ia.dart';

void main() {
  // On the test host (not Android) the optional plugins are skipped; initFeaturesIa must complete without throwing.
  test('initFeaturesIa never throws', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await expectLater(initFeaturesIa(), completes);
  });

  test(
    'runs the pre-restore copy cleanup and the inbox purge at startup',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final steps = <String>[];

      await expectLater(
        initFeaturesIa(
          deletePreCopies: () async => steps.add('copies'),
          purgeInbox: () async => steps.add('purge'),
        ),
        completes,
      );

      expect(steps, ['copies', 'purge']);
    },
  );

  test(
    'a startup step that throws does not stop initFeaturesIa or the other step',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final steps = <String>[];

      await expectLater(
        initFeaturesIa(
          deletePreCopies: () async {
            steps.add('copies');
            throw StateError('copies failed');
          },
          purgeInbox: () async {
            steps.add('purge');
            throw StateError('purge failed');
          },
        ),
        completes,
      );

      expect(steps, ['copies', 'purge']);
    },
  );
}
