import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/features_ia.dart';

void main() {
  // On the test host (not Android) the optional plugins are skipped; initFeaturesIa must complete without throwing.
  test('initFeaturesIa never throws', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await expectLater(initFeaturesIa(), completes);
  });
}
