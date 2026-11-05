// E004 test 4: time of the Argon2id derivation of the backup password on the device, with the production parameters.
// Built in profile mode (AOT) with: flutter build apk --profile -t integration_test/finanzas_ia/argon2_profile_main.dart
// The result is printed to logcat as `ARGON2_MS`.
import 'package:flutter/material.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final params = kDefaultKdfParams;
  // ignore: avoid_print
  print(
    'ARGON2_PARAMS memoryKiB=${params.memoryKiB} iterations=${params.iterations} parallelism=${params.parallelism}',
  );
  // The first run also loads the isolate; the rest are the steady state.
  for (var run = 1; run <= 6; run++) {
    final watch = Stopwatch()..start();
    await createBackupKey('E2e-Clave-Buena-2026');
    // ignore: avoid_print
    print('ARGON2_MS run=$run ms=${watch.elapsedMilliseconds}');
  }
  // ignore: avoid_print
  print('ARGON2_DONE');
}
