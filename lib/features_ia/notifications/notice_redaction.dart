// Masks the codes and long numbers of a bank notice before it is saved or sent to the AI (T002). Owner: w-avisos.

final _oneTimeCode = RegExp(
  r'\b(clave|c[oó]digo|token|otp|pin|contrase[ñn]a|password|cvv|cvc)\b([^\d\n$]{0,30}?)\d{3,}',
  caseSensitive: false,
);

// 13 to 19 digits, written together or in groups of four: a card number.
final _cardNumber = RegExp(r'\b\d{4}(?:[ -]\d{4}){2,4}\b|\b\d{13,19}\b');

final _longNumber = RegExp(r'\d{6,}');

final _currencyBefore = RegExp(r'(\$|\bcop|\busd)\s*$', caseSensitive: false);
final _currencyAfter = RegExp(r'^\s*(pesos|cop|usd)\b', caseSensitive: false);

/// Hides one-time codes, card numbers (only the last 4 digits stay) and any other run of 6 or more
/// digits, such as an account or document number. Amounts written with a currency (`$450000`,
/// `450000 pesos`) or with separators (`$45.900`) are left as they are.
String maskSensitive(String text) {
  var out = text.replaceAllMapped(_oneTimeCode, (m) => '${m[1]}${m[2]}****');
  out = _maskDigits(out, _cardNumber, (m) {
    final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
    return '****${digits.substring(digits.length - 4)}';
  });
  return _maskDigits(out, _longNumber, (_) => '******');
}

// Clauses end at a sentence end, a line break or a comma/semicolon followed by a space (the comma of
// `$15.430.200,00` is followed by a digit, so amounts stay whole).
final _clauseBreak = RegExp(r'(?<=[.!?,;])\s+|\n+');
final _balanceWord = RegExp(
  r'\b(saldo|sdo|disponible|cupo|l[ií]mite|deuda|total|en\s+cuenta|titular|a\s+nombre\s+de)\b',
  caseSensitive: false,
);

/// The text without the clauses that talk about a balance, an available amount, a credit limit, a debt, a total\n/// or the holder.
String withoutBalanceClauses(String text) => text
    .split(_clauseBreak)
    .where((c) => c.trim().isNotEmpty && !_balanceWord.hasMatch(c))
    .join(' ');

// What the AI may see besides words: an amount (`$45.900`, `45900 COP`) or a date (`03/11/2026`).
final _kept = RegExp(
  r'(\$\s*\d[\d.,]*|\bCOP\s*\d[\d.,]*|\d[\d.,]*\s*(?:COP|pesos)\b|\b\d{1,2}/\d{1,2}/\d{2,4}\b)|\d+',
  caseSensitive: false,
);

const _maxAiChars = 500;

/// The movement sentence for the AI: no balance, available or limit clauses, and every digit run
/// (account, card, phone, document, time...) masked except the amount and the date.
String redactForAi(String text) {
  final out = withoutBalanceClauses(
    text,
  ).replaceAllMapped(_kept, (m) => m[1] ?? '****');
  final flat = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= _maxAiChars ? flat : flat.substring(0, _maxAiChars);
}

String _maskDigits(String text, RegExp pattern, String Function(Match) mask) =>
    text.replaceAllMapped(pattern, (m) {
      final before = text.substring(0, m.start);
      final after = text.substring(m.end);
      if (_currencyBefore.hasMatch(before) || _currencyAfter.hasMatch(after)) {
        return m[0]!;
      }
      return mask(m);
    });
