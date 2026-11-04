import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/brand_migration.dart';
import 'package:monekin/brand/brand_tokens.dart';

void main() {
  late Directory dir;
  late File marker;
  String? saved;

  Future<bool> run(String? accent) => migrateToBrandAccent(
    currentAccent: accent,
    saveAccent: (hex) async => saved = hex,
    marker: marker,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('brand_migration_');
    marker = File('${dir.path}/$brandMigrationFileName');
    saved = null;
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test(
    '"auto" without the marker moves to the brand accent and saves it',
    () async {
      expect(await run('auto'), isTrue);

      expect(saved, BrandTokens.accentHex);
      expect(marker.existsSync(), isTrue);
    },
  );

  test('"auto" with the marker is left alone', () async {
    marker.writeAsStringSync('{"done":true}');

    expect(await run('auto'), isFalse);

    expect(saved, isNull);
  });

  test('another accent is left alone', () async {
    expect(await run('2E7D32'), isFalse);

    expect(saved, isNull);
  });

  test('turning dynamic colors back on later is respected', () async {
    expect(await run('auto'), isTrue);

    saved = null;
    expect(await run('auto'), isFalse);

    expect(saved, isNull);
  });

  test(
    'a custom accent also sets the marker, so a later "auto" stays',
    () async {
      await run('2E7D32');
      expect(marker.existsSync(), isTrue);

      expect(await run('auto'), isFalse);
      expect(saved, isNull);
    },
  );
}
