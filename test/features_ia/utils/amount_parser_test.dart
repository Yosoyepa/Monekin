// Port of pkg/aiimport/amount_test.go (T001): same inputs and expected amounts, formatted with 2 decimals.
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';

const _validCases = <(String, String)>[
  ('1.234.567', '1234567.00'),
  ('1.234.567,89', '1234567.89'),
  ('45.900', '45900.00'),
  ('45,900.00', '45900.00'),
  ('12.34', '12.34'),
  ('12,34', '12.34'),
  ('1,234', '1234.00'),
  ('\$ 45.900', '45900.00'),
  ('\$45.900', '45900.00'),
  ('COP 1.234.567', '1234567.00'),
  ('cop 1.234.567,50', '1234567.50'),
  ('45.900 COP', '45900.00'),
  ('\$ 1.234.567,89 COP', '1234567.89'),
  ('45900', '45900.00'),
  ('45900.5', '45900.50'),
  ('45900,5', '45900.50'),
  ('0', '0.00'),
  ('0,5', '0.50'),
  ('0.5', '0.50'),
  ('.5', '0.50'),
  ('7', '7.00'),
  ('100.000', '100000.00'),
  ('100,000', '100000.00'),
  ('1,234,567', '1234567.00'),
  ('1,234,567.89', '1234567.89'),
  ('1.234,5', '1234.50'),
  ('1 234 567', '1234567.00'),
  ('  45.900  ', '45900.00'),
  ('+45.900', '45900.00'),
  ('-45.900', '-45900.00'),
  ('-\$ 1.200,50', '-1200.50'),
  ('−45.900', '-45900.00'),
  ('999.999.999', '999999999.00'),
  ('1234.56', '1234.56'),
  ('1234,56', '1234.56'),
  ('12.000.000', '12000000.00'),
  ('2.500,00', '2500.00'),
  ('2,500.00', '2500.00'),
  ('10.50', '10.50'),
];

const _ambiguousCases = <String>[
  '',
  ' ',
  '\$',
  '-',
  'abc',
  '12a',
  '1.2.3',
  '1.23.456',
  '1,2,3',
  '1.234,567',
  '12.3456',
  '12,3456',
  '0.123',
  '0,123',
  '1234.567',
  '01.234',
  '12.',
  '12,',
  '1.234.56',
  '(45.900)',
  '45.900 pesos',
  '1.234.567.890.123.456.789',
  '1e5',
  '1,234.567,89',
  '99999999999999999',
];

void main() {
  group('parseLocalizedAmount, valid amounts', () {
    for (final (input, expected) in _validCases) {
      test('"$input"', () {
        expect(parseLocalizedAmount(input)?.toStringAsFixed(2), expected);
      });
    }
  });

  group('parseLocalizedAmount, Unicode blanks (not in the Go tests)', () {
    test('no-break space and narrow no-break space are blanks', () {
      expect(
        parseLocalizedAmount('45.900\u00A0COP')?.toStringAsFixed(2),
        '45900.00',
      );
      expect(parseLocalizedAmount('1\u202F234')?.toStringAsFixed(2), '1234.00');
    });
  });
  group('parseLocalizedAmount, ambiguous amounts', () {
    for (final input in _ambiguousCases) {
      test('"$input"', () {
        expect(parseLocalizedAmount(input), isNull);
      });
    }
  });
}
