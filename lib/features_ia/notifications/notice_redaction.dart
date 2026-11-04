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

String _maskDigits(String text, RegExp pattern, String Function(Match) mask) =>
    text.replaceAllMapped(pattern, (m) {
      final before = text.substring(0, m.start);
      final after = text.substring(m.end);
      if (_currencyBefore.hasMatch(before) || _currencyAfter.hasMatch(after)) {
        return m[0]!;
      }
      return mask(m);
    });
