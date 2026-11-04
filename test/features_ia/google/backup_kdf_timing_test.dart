// Measures Argon2id with the parameters kept in the header. Prints the times; the
// assertion is a loose ceiling, because the phone is slower than the host.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';

void main() {
  test(
    'Argon2id with the default cost stays well under 3 s on the host',
    () async {
      final salt = Uint8List(kSaltBytes);
      for (var run = 1; run <= 3; run++) {
        final watch = Stopwatch()..start();
        await deriveKeyBytes(
          'a password of ten+ chars',
          salt,
          kDefaultKdfParams,
        );
        watch.stop();
        // ignore: avoid_print
        print(
          'KDF run $run: ${watch.elapsedMilliseconds} ms '
          '(${kDefaultKdfParams.memoryKiB} KiB, ${kDefaultKdfParams.iterations} it, '
          'p=${kDefaultKdfParams.parallelism})',
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      }
    },
  );
}
