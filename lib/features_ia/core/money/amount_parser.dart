// Colombian amount parsing (T002). Owner: w-utils.
// Port of pkg/aiimport/amount.go from the ezBookkeeping fork (T001), with all its test cases.
//
// Rules: `1.234.567` = 1234567; `45.900` = 45900; `12,34` = 12.34; `1.234.567,89` = 1234567.89;
// `45,900.00` = 45900; `$ 45.900` and `COP 45.900` = 45900; a leading `-` or `+` sets the sign.
// Returns null when the format is not clear (e.g. `1.23.456`, `(45.900)`, `12.`).

final _copWord = RegExp('cop', caseSensitive: false);

// Same blanks as Go's unicode.IsSpace, plus the `$` sign
final _spacesAndDollar = RegExp(
  r'[\t\n\v\f\r \x85\xA0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000$]',
);

final _amountChars = RegExp(r'^[0-9.,]+$');

// Max count of digits (integer and decimals) that fit the amount range of the transactions
const _maxAmountDigits = 17;

/// Parses an amount written in Colombian or US format and returns its value, or null if the format is not clear.
double? parseLocalizedAmount(String raw) {
  var text = raw
      .replaceAll(_copWord, '')
      .replaceAll(_spacesAndDollar, '')
      .replaceAll('\u2212', '-');

  var negative = false;

  if (text.startsWith('-')) {
    negative = true;
    text = text.substring(1);
  } else if (text.startsWith('+')) {
    text = text.substring(1);
  }

  if (!_amountChars.hasMatch(text)) return null;

  final parts = _splitAmount(text);

  if (parts == null) return null;

  final (integerPart, decimalPart) = parts;

  if (decimalPart.length > 2 || integerPart.length + 2 > _maxAmountDigits) {
    return null;
  }

  final integer = integerPart.isEmpty ? '0' : integerPart;
  final hundredths = int.tryParse('$integer${decimalPart.padRight(2, '0')}');

  if (hundredths == null) return null;

  return (negative ? -hundredths : hundredths) / 100;
}

/// Splits digits, dots and commas into integer and decimal digits, or returns null when the separators are not clear.
(String, String)? _splitAmount(String s) {
  final dots = _count(s, '.');
  final commas = _count(s, ',');

  if (dots == 0 && commas == 0) return (s, '');

  if (dots > 0 && commas > 0) {
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    final decimal = lastComma > lastDot ? ',' : '.';
    final thousands = decimal == '.' ? ',' : '.';
    final decimalIndex = decimal == '.' ? lastDot : lastComma;

    if (_count(s, decimal) != 1) return null;

    final integerPart = s.substring(0, decimalIndex);
    final decimalPart = s.substring(decimalIndex + 1);
    final validGrouping = _isValidThousandsGrouping(integerPart, thousands);

    if (decimalPart.isEmpty || !validGrouping) return null;

    return (integerPart.replaceAll(thousands, ''), decimalPart);
  }

  final separator = commas > 0 ? ',' : '.';

  if (_count(s, separator) > 1) {
    if (!_isValidThousandsGrouping(s, separator)) return null;

    return (s.replaceAll(separator, ''), '');
  }

  final index = s.indexOf(separator);
  final left = s.substring(0, index);
  final right = s.substring(index + 1);

  // A single separator followed by exactly 3 digits is a thousands separator, but only when the left part looks like a group
  if (right.length == 3) {
    return left.isNotEmpty && left.length <= 3 && left[0] != '0'
        ? (left + right, '')
        : null;
  }

  if (right.length == 1 || right.length == 2) return (left, right);

  return null;
}

/// Whether [s] is one group of 1-3 digits (not starting with 0) followed by groups of exactly 3 digits
bool _isValidThousandsGrouping(String s, String separator) {
  final groups = s.split(separator);

  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    final valid = i == 0
        ? group.isNotEmpty && group.length <= 3 && group[0] != '0'
        : group.length == 3;

    if (!valid) return false;
  }

  return true;
}

int _count(String s, String separator) => s.split(separator).length - 1;
