import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/cards/card_map.dart';

void main() {
  late Directory documents;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('card_map_test');
    CardMapService.instance.debugDirectory = () async => documents;
  });

  tearDown(() {
    CardMapService.instance.debugDirectory = null;
    documents.deleteSync(recursive: true);
  });

  File mapFile() => File('${documents.path}/finanzas_ia/card_map.json');

  test('load returns an empty map when there is no file yet', () async {
    expect(await CardMapService.instance.load(), isEmpty);
  });

  test('save and load return the same last 4 digits and account ids', () async {
    await CardMapService.instance.save({'1234': 'acc-1', '0042': 'acc-2'});

    expect(await CardMapService.instance.load(), {
      '1234': 'acc-1',
      '0042': 'acc-2',
    });
    expect(await CardMapService.instance.accountFor('1234'), 'acc-1');
    expect(await CardMapService.instance.accountFor('9999'), isNull);
  });

  test('the file holds only the last 4 digits and the account id', () async {
    await CardMapService.instance.save({'1234': 'acc-1'});

    expect(mapFile().readAsStringSync(), '{"1234":"acc-1"}');
  });

  test('saving a map without a card removes it', () async {
    await CardMapService.instance.save({'1234': 'acc-1', '0042': 'acc-2'});
    await CardMapService.instance.save({'0042': 'acc-2'});

    expect(await CardMapService.instance.accountFor('1234'), isNull);
    expect(await CardMapService.instance.accountFor('0042'), 'acc-2');
  });

  test('rejects anything but exactly 4 digits and writes nothing', () async {
    for (final bad in ['123', '12345', '12a4', '']) {
      await expectLater(
        CardMapService.instance.save({bad: 'acc-1'}),
        throwsA(isA<ArgumentError>()),
        reason: 'key "$bad"',
      );
    }

    expect(mapFile().existsSync(), isFalse);
  });
}
