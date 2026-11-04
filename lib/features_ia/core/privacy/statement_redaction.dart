// What the AI provider receives of a bank statement: the movement lines when they can be told apart, and no account,
// card or document numbers, emails or phones. Dates, amounts and movement descriptions stay, reconciliation needs them.
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
final _longNumber = RegExp(r'(?<![\d.,])\d{8,}(?![\d]|[.,]\d)');
final _compactDate = RegExp(
  r'^(?:19|20)\d\d(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])$',
);
final _token = RegExp(r'\S+');

/// Needs at least this many dated lines with an amount to trust the movement table.
const _minMovementLines = 3;

/// The statement text reduced to the movement lines (with the column headers and the opening and closing balances)
/// when the table is found (unless [reduce] is false), and with identifiers masked either way.
String redactStatementText(String text, {bool reduce = true}) {
  final lines = const LineSplitter().convert(text);
  final reduceLines =
      reduce && lines.where(_isMovementLine).length >= _minMovementLines;
  final out = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty) {
      // A blank line separates stray amounts from the rows around them: keep one.
      if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
    } else if (!reduceLines || _isKept(line)) {
      out.add(maskStatementIdentifiers(line));
    }
  }
  return out.join('\n').trim();
}

bool _isMovementLine(String line) =>
    _date.hasMatch(line) && _money.hasMatch(line);

bool _isKept(String line) {
  final hasDate = _date.hasMatch(line);
  if (!hasDate && _identityLine.hasMatch(line) && !_balance.hasMatch(line)) {
    return false;
  }
  if (hasDate || _money.hasMatch(line) || _balance.hasMatch(line)) return true;
  return _columnWord.allMatches(line).length >= 2;
}

/// [text] with emails, phones, cards, account and document numbers replaced by a tag.
String maskStatementIdentifiers(String text) {
  var masked = text.replaceAllMapped(
    _token,
    (m) => m[0]!.contains('@') ? '[email]' : m[0]!,
  );
  masked = masked.replaceAllMapped(_keywordNumber, (m) => '${m[1]}${m[2]}[id]');
  masked = masked
      .replaceAll(_nit, '[id]')
      .replaceAll(_dottedDocument, '[id]')
      .replaceAll(_spacedCard, '[card]')
      .replaceAll(_maskedCard, '[card]')
      .replaceAll(_phone, '[phone]');
  return masked.replaceAllMapped(_longNumber, (m) {
    final digits = m[0]!;
    if (_compactDate.hasMatch(digits)) return digits;
    final before = masked.substring(0, m.start).trimRight();
    return before.endsWith(r'$') ? digits : '[id]';
  });
}
