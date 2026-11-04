// What the AI provider receives of a bank statement: the movement lines when they can be told apart, never the header lines
// (holder, address, document), and no account, card or document numbers, emails or phones. Dates, amounts and movement
// descriptions stay, reconciliation needs them.
// Every pattern here is bounded or anchored so that a long line cannot make it backtrack.
import 'dart:convert';

final _date = RegExp(
  r'\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b|\b\d{4}[/\-.]\d{1,2}[/\-.]\d{1,2}\b|\b\d{1,2}\s+(?:ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)[a-z]*\.?\s+\d{2,4}\b',
  caseSensitive: false,
);

/// An amount with thousands or decimals: `3.200.000,00`, `45.900`, `12,50`, `1,234.50`.
final _money = RegExp(
  r'\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+[.,]\d{2}\b',
);

final _balance = RegExp(
  r'saldo\s+(?:inicial|anterior|final|nuevo|actual)|nuevo\s+saldo',
  caseSensitive: false,
);

final _columnWord = RegExp(
  r'\b(?:fecha|descripci[oó]n|concepto|detalle|valor|d[eé]bitos?|cr[eé]ditos?|saldo|monto|importe)\b',
  caseSensitive: false,
);

/// Lines without a date that describe the holder or the account, not a movement.
final _identityLine = RegExp(
  r'\b(?:saldo\s+(?:disponible|total|promedio|en\s+cuenta|bolsillo|canje)|cupo|disponible|titular|cliente|se[nñ]or(?:a)?|nombre|direcci[oó]n|correo|e-?mail|tel[eé]fono|celular|nit|c\.?c\.?|c[eé]dula|documento|identificaci[oó]n)\b',
  caseSensitive: false,
);

/// A keyword for an account, card or document followed by its masked form or by hyphenated groups (`123-456789-01`).
/// Plain and dotted numbers are left to the number rules below, so an amount after the word "cuenta" is never taken.
final _keywordNumber = RegExp(
  r'\b(cuenta|cta|c\.?c|c[eé]dula|nit|documento|identificaci[oó]n|tarjeta)\b'
  r'((?:\s+(?:de|ahorros?|corriente|n[oó]mina|no|nro|n[uú]mero|num)\.?)*\s*[:#.\-]?\s*)'
  r'(?:[*•X]{2,}[ -]?\d{2,4}|\d{2,}(?:-\d+){1,3})',
  caseSensitive: false,
);

final _nit = RegExp(r'\b\d{1,3}(?:\.\d{3}){2}-\d\b');
final _dottedDocument = RegExp(r'\b\d{1,3}(?:\.\d{3}){3}\b(?![.,]\d)');
final _spacedCard = RegExp(r'(?<![\d.,])(?:\d{4}[ -]){3}\d{3,4}(?!\d)');
final _maskedCard = RegExp(
  r'(?<![*•X])[*•X]{2,}(?:[ -][*•X]{2,})*[ -]?\d{2,4}(?!\d)',
);
final _phone = RegExp(
  r'(?<![\d.,])(?:\+?57[ -]?)?(?:3\d{2}[ -]?\d{3}[ -]?\d{4}|\(?60\d\)?[ -]?\d{3}[ -]?\d{4})(?![\d]|[.,]\d)|\+\d{1,3}[ -]?\d(?:[ -]?\d){6,11}(?!\d)',
);
final _longNumber = RegExp(r'(?<![\d.,])\d{6,}(?![\d]|[.,]\d)');

/// Dotted groups without decimals, a document such as 1.234.567; an amount with decimals or a currency symbol is not.
final _dottedNumber = RegExp(
  r'(?<![\d.,])\d{1,3}(?:\.\d{3}){2,}(?![\d]|[.,]\d)',
);

/// Three or more groups of digits split by spaces or hyphens, 1234 5678 90.
final _groupedNumber = RegExp(
  r'(?<![\d.,/-])\d{2,4}(?:[ -]\d{2,4}){2,}(?![\d]|[.,]\d)',
);

/// A date split by spaces, which _date does not take.
final _spacedDate = RegExp(
  r'^(?:\d{1,2}[ -]\d{1,2}[ -]\d{2,4}|\d{4}[ -]\d{1,2}[ -]\d{1,2})$',
);

final _currencyBefore = RegExp(
  r'(?:\$|€|\b(?:COP|USD|EUR))\s*$',
  caseSensitive: false,
);

/// A label of a holder, address or document followed by its value, on a line that is not a movement.
final _labelValue = RegExp(
  r'\b(titular|nombre|cliente|se[nñ]or(?:a)?|a\s+nombre\s+de|direcci[oó]n|documento|identificaci[oó]n|c[eé]dula|nit|c\.?c\.?)\b(\s*:\s*)[^\n]{1,80}',
  caseSensitive: false,
);

final _nameLabel = RegExp(
  r'^(?:titular|nombre|cliente|se[nñ]or(?:a)?|a\s+nombre\s+de)$',
  caseSensitive: false,
);
final _addressLabel = RegExp(r'^direcci[oó]n$', caseSensitive: false);
final _compactDate = RegExp(
  r'^(?:19|20)\d\d(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])$',
);
final _token = RegExp(r'\S+');

/// Needs at least this many dated lines with an amount to trust the movement table.
const _minMovementLines = 3;

/// The statement text reduced to the movement lines (with the column headers and the opening and closing balances)
/// when the table is found, and with identifiers masked either way. When the table is not found the header lines
/// (holder, address, document) are still left out.
String redactStatementText(String text) {
  final lines = const LineSplitter().convert(text);
  final reduceLines = lines.where(_isMovementLine).length >= _minMovementLines;
  final out = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty) {
      // A blank line separates stray amounts from the rows around them: keep one.
      if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
    } else if (!_isHeaderLine(line) && (!reduceLines || _isKept(line))) {
      out.add(maskStatementIdentifiers(line));
    }
  }
  return out.join('\n').trim();
}

bool _isMovementLine(String line) =>
    _date.hasMatch(line) && _money.hasMatch(line);

/// A line about the holder or the account, not about a movement or the statement balances.
bool _isHeaderLine(String line) =>
    !_date.hasMatch(line) &&
    _identityLine.hasMatch(line) &&
    !_balance.hasMatch(line);

bool _isKept(String line) {
  final hasDate = _date.hasMatch(line);
  if (hasDate || _money.hasMatch(line) || _balance.hasMatch(line)) return true;
  return _columnWord.allMatches(line).length >= 2;
}

/// [text] with emails, phones, cards, account and document numbers replaced by a tag.
String maskStatementIdentifiers(String text) {
  var masked = text.replaceAllMapped(
    _token,
    (m) => m[0]!.contains('@') ? '[email]' : m[0]!,
  );
  masked = masked
      .split('\n')
      .map(
        (line) => _date.hasMatch(line)
            ? line
            : line.replaceAllMapped(_labelValue, (m) {
                final label = m[1]!;
                final tag = _nameLabel.hasMatch(label)
                    ? '[name]'
                    : _addressLabel.hasMatch(label)
                    ? '[address]'
                    : '[id]';
                return '$label${m[2]}$tag';
              }),
      )
      .join('\n');
  masked = masked.replaceAllMapped(_keywordNumber, (m) => '${m[1]}${m[2]}[id]');
  masked = masked
      .replaceAll(_nit, '[id]')
      .replaceAll(_dottedDocument, '[id]')
      .replaceAll(_spacedCard, '[card]')
      .replaceAll(_maskedCard, '[card]')
      .replaceAll(_phone, '[phone]');
  return _maskLongNumbers(masked);
}

/// Masks the runs of six or more digits that are not an amount with decimals or a currency symbol, nor a date.
String _maskLongNumbers(String text) {
  String mask(RegExp pattern, String text, {bool skipDates = false}) =>
      text.replaceAllMapped(pattern, (m) {
        final digits = m[0]!;
        if (_compactDate.hasMatch(digits)) return digits;
        if (skipDates &&
            (_date.hasMatch(digits) || _spacedDate.hasMatch(digits))) {
          return digits;
        }
        if (digits.replaceAll(RegExp(r'\D'), '').length < 6) return digits;
        if (_currencyBefore.hasMatch(text.substring(0, m.start).trimRight())) {
          return digits;
        }
        return '[id]';
      });
  var masked = mask(_longNumber, text);
  masked = mask(_dottedNumber, masked);
  return mask(_groupedNumber, masked, skipDates: true);
}
