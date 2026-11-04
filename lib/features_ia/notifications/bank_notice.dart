// Local (regex) templates for bank notifications (T002). Owner: w-avisos.
//
// Sources of the formats:
//  - Bancolombia (purchase, payment, transfer out/in): public synthetic fixtures of the project
//    AlejandroBlanco2001/Untyped (tests/fixtures/sms/bancolombia), which copy the real bank wording:
//      «Compraste $32.500,00 en UBER RIDES con tu T.Deb *1234, el 15/09/2026 a las 20:35.»
//      «Bancolombia: Pagaste $62.000,00 a Pexto Capital SAS desde tu producto 1234 el 13/09/2026 22:20:37.»
//      «Bancolombia: Transferiste $75.000,00 desde tu cuenta *1234 a la cuenta *00001111222 el 13/09/26 a las 23:54.»
//      «Bancolombia: Recibiste una transferencia por $185,000.00 de Juan Pérez en tu cuenta *1234, el 14/09/26 a las 01:40.»
//    Withdrawals («Retiraste») and credit cards («T.Cred») follow the same wording.
//  - Nequi: the push body has the amount inside a phrase («Ana te envió 300000»).
//  - Davivienda, DaviPlata, Nu, BBVA, Banco de Bogotá: no public sample of the real text was found; the
//    templates follow the verbs those banks use («Compra por $X en Y», «Pagaste», «Recibiste», «Retiro por»).
//    They are not verified on a real device: unknown texts go to the AI or to the inbox as pending.
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/notifications/bank_apps.dart';
import 'package:monekin/features_ia/notifications/notice_redaction.dart';

enum NoticeKind {
  purchase,
  payment,
  transferOut,
  withdrawal,
  transferIn,
  deposit,
}

extension NoticeKindX on NoticeKind {
  bool get isIncome =>
      this == NoticeKind.transferIn || this == NoticeKind.deposit;

  TransactionType get type =>
      isIncome ? TransactionType.income : TransactionType.expense;
}

class BankNotice {
  const BankNotice({
    required this.kind,
    required this.amount,
    required this.date,
    this.merchant,
    this.last4,
  });

  final NoticeKind kind;

  /// Always positive.
  final double amount;
  final DateTime date;

  /// Shop or person; null when the text does not say.
  final String? merchant;
  final String? last4;

  TransactionType get type => kind.type;
}

typedef AmountParser = double? Function(String raw);

class _Template {
  _Template(this.banks, this.kind, String pattern)
    : regex = RegExp(
        pattern.replaceAll('{A}', _amount).replaceAll('{M}', _merchant),
        caseSensitive: false,
        unicode: true,
      );

  final Set<BankId> banks;
  final NoticeKind kind;
  final RegExp regex;
}

const _amount = r'\$?\s*(?<amount>\d[\d.,]*\d|\d)(?:\s*COP)?';

// A merchant ends where the next clause of the sentence starts.
const _merchant =
    r'(?<merchant>.+?)(?=\s+(?:con|desde|usando|tarjeta|TC|TD|T\.|el|en\s+tu|a\s+las|fue)\b|[,;]|\.?\s*$)';

const _bc = BankId.bancolombia;
const _nq = BankId.nequi;
const _dv = BankId.davivienda;
const _dp = BankId.daviplata;
const _nu = BankId.nu;
const _bb = BankId.bbva;
const _bg = BankId.bancoDeBogota;

final List<_Template> _templates = [
  // Bancolombia
  _Template({_bc}, NoticeKind.purchase, r'Compraste\s+{A}\s+en\s+{M}'),
  _Template({_bc}, NoticeKind.payment, r'Pagaste\s+{A}\s+a\s+{M}'),
  _Template(
    {_bc},
    NoticeKind.transferOut,
    r'Transferiste\s+{A}\s+desde\s+tu\s+(?:cuenta|producto)\s+\*?\d+(?:\s+a\s+(?:la\s+cuenta\s+|la\s+llave\s+)?(?<merchant>[*@]?\w+))?',
  ),
  _Template({_bc}, NoticeKind.withdrawal, r'Retiraste\s+{A}(?:\s+en\s+{M})?'),
  _Template(
    {_bc},
    NoticeKind.transferIn,
    r'Recibiste\s+una\s+transferencia\s+por\s+{A}\s+de\s+{M}',
  ),
  _Template(
    {_bc},
    NoticeKind.deposit,
    r'Recibiste\s+(?:un\s+pago|una\s+consignaci[oó]n|un\s+abono|un\s+dep[oó]sito)\s+por\s+{A}(?:\s+de\s+{M})?',
  ),
  // Nequi
  _Template(
    {_nq},
    NoticeKind.transferIn,
    r'(?<merchant>[^.:!¡\n]+?)\s+te\s+envi[oó]\s+{A}',
  ),
  _Template({_nq}, NoticeKind.deposit, r'Recibiste\s+{A}(?:\s+de\s+{M})?'),
  _Template({_nq}, NoticeKind.purchase, r'Compraste\s+{A}\s+en\s+{M}'),
  _Template({_nq}, NoticeKind.payment, r'Pagaste\s+{A}\s+(?:en|a)\s+{M}'),
  _Template({_nq}, NoticeKind.transferOut, r'Enviaste\s+{A}\s+a\s+{M}'),
  _Template(
    {_nq},
    NoticeKind.withdrawal,
    r'Retiraste\s+{A}(?:\s+(?:en|del?)\s+{M})?',
  ),
  // Davivienda and DaviPlata
  _Template(
    {_dv, _dp},
    NoticeKind.purchase,
    r'(?:Realizaste\s+una\s+compra|Compra(?:\s+(?:exitosa|aprobada))?)\s+por\s+{A}\s+en\s+{M}',
  ),
  _Template(
    {_dv, _dp},
    NoticeKind.payment,
    r'(?:Pagaste|Pago(?:\s+exitoso)?\s+por)\s+{A}\s+(?:a|en)\s+{M}',
  ),
  _Template(
    {_dv, _dp},
    NoticeKind.transferOut,
    r'(?:Transferiste|Enviaste|Pasaste)\s+{A}\s+a\s+{M}',
  ),
  _Template(
    {_dv, _dp},
    NoticeKind.withdrawal,
    r'(?:Retiro(?:\s+exitoso)?\s+por|Retiraste)\s+{A}(?:\s+en\s+{M})?',
  ),
  _Template(
    {_dv, _dp},
    NoticeKind.transferIn,
    r'Recibiste\s+(?:una\s+transferencia\s+)?(?:por\s+)?{A}\s+de\s+{M}',
  ),
  _Template(
    {_dv, _dp},
    NoticeKind.transferIn,
    r'(?<merchant>[^.:!¡\n]+?)\s+te\s+(?:transfiri[oó]|envi[oó])\s+{A}',
  ),
  // Nu
  _Template(
    {_nu},
    NoticeKind.purchase,
    r'(?:Compra\s+aprobada(?:\s+(?:de|por))?:?|Tu\s+compra\s+(?:de|por)|Compraste)\s+{A}\s+en\s+{M}',
  ),
  _Template({_nu}, NoticeKind.payment, r'Pagaste\s+{A}\s+(?:a|en)\s+{M}'),
  _Template({_nu}, NoticeKind.transferOut, r'Enviaste\s+{A}\s+a\s+{M}'),
  _Template({_nu}, NoticeKind.transferIn, r'Recibiste\s+{A}\s+de\s+{M}'),
  _Template({_nu}, NoticeKind.deposit, r'Te\s+(?:abonamos|depositamos)\s+{A}'),
  // BBVA and Banco de Bogotá
  _Template(
    {_bb, _bg},
    NoticeKind.purchase,
    r'Compra\s+(?:aprobada\s+)?(?:por|de)\s+{A}\s+en\s+{M}',
  ),
  _Template(
    {_bb, _bg},
    NoticeKind.withdrawal,
    r'Retiro\s+(?:por|de)\s+{A}(?:\s+en\s+{M})?',
  ),
  _Template(
    {_bb, _bg},
    NoticeKind.transferOut,
    r'Transferencia\s+(?:enviada\s+)?por\s+{A}\s+a\s+{M}',
  ),
  _Template(
    {_bb, _bg},
    NoticeKind.transferIn,
    r'Transferencia\s+recibida\s+por\s+{A}(?:\s+de\s+{M})?',
  ),
  _Template(
    {_bb, _bg},
    NoticeKind.payment,
    r'Pago\s+(?:de\s+\w+\s+)?por\s+{A}\s+a\s+{M}',
  ),
];

final _datePattern = RegExp(
  r'(?<d>\d{1,2})/(?<m>\d{1,2})/(?<y>\d{4}|\d{2})(?:\s*(?:,|a\s+las|-)?\s*(?<h>\d{1,2}):(?<min>\d{2})(?::(?<s>\d{2}))?)?',
  caseSensitive: false,
);

final _last4Pattern = RegExp(
  r'(?:terminad[ao]\s+en|T\.\s*(?:Deb|Cred)|tarjeta|cuenta|producto|\bTC\b|\bTD\b)[^\d\n]{0,20}?\*?\d*?(?<l>\d{4})\b',
  caseSensitive: false,
);

String? _group(RegExpMatch m, String name) =>
    m.groupNames.contains(name) ? m.namedGroup(name) : null;

String? _cleanMerchant(String? raw) {
  if (raw == null) return null;
  var s = raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^["\x27]+|["\x27.,;:!]+$'), '')
      .trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^\*?\d{5,}$').hasMatch(s)) {
    s = 'Transferencia *${s.substring(s.length - 4)}';
  }
  return s;
}

DateTime _extractDate(String text, DateTime fallback) {
  final m = _datePattern.firstMatch(text);
  if (m == null) return fallback;
  final day = int.parse(m.namedGroup('d')!);
  final month = int.parse(m.namedGroup('m')!);
  var year = int.parse(m.namedGroup('y')!);
  if (year < 100) year += 2000;
  if (month < 1 || month > 12 || day < 1 || day > 31) return fallback;
  final h = m.namedGroup('h');
  final hour = h == null ? fallback.hour : int.parse(h);
  final minute = h == null ? fallback.minute : int.parse(m.namedGroup('min')!);
  final second = m.namedGroup('s') == null ? 0 : int.parse(m.namedGroup('s')!);
  if (hour > 23 || minute > 59 || second > 59) return fallback;
  final date = DateTime(year, month, day, hour, minute, second);
  // The calendar rolled over (31/02) -> not a real date.
  return date.month == month ? date : fallback;
}

String _normalize(String s) =>
    s.replaceAll(' ', ' ').replaceAll(RegExp(r'[ \t\r\n]+'), ' ').trim();

/// Reads one bank notification with the local templates.
///
/// [title] and [content] are the two fields of an Android notification; each is tried alone and then
/// joined, so the text works whichever field carries the sentence. Returns null when no template fits.
BankNotice? parseBankNotice({
  required String title,
  required String content,
  required DateTime receivedAt,
  BankId? bank,
  AmountParser parse = parseLocalizedAmount,
}) {
  final candidates = {
    _normalize(content),
    _normalize('$title: $content'),
    _normalize(title),
  }.where((s) => s.isNotEmpty);

  final ordered = [
    ..._templates.where((t) => bank != null && t.banks.contains(bank)),
    ..._templates.where((t) => bank == null || !t.banks.contains(bank)),
  ];

  for (final text in candidates) {
    for (final t in ordered) {
      final m = t.regex.firstMatch(text);
      if (m == null) continue;
      final rawAmount = _group(m, 'amount');
      final amount = rawAmount == null ? null : parse(rawAmount);
      if (amount == null || amount <= 0) continue;
      final last4 = _last4Pattern.firstMatch(text)?.namedGroup('l');
      return BankNotice(
        kind: t.kind,
        amount: amount.abs(),
        date: _extractDate(text, receivedAt),
        merchant: _cleanMerchant(_group(m, 'merchant')),
        last4: last4,
      );
    }
  }
  return null;
}

// An amount as banks write it: `$45.900`, `$ 45.900 COP`, `COP 45900` or `45900 pesos`.
final _genericAmount = RegExp(
  r'(?:\$\s*|\bCOP\s*)(?<a>\d[\d.,]*\d|\d)(?:\s*(?:COP|pesos)\b)?|(?<b>\d[\d.,]*\d|\d)\s*(?:COP|pesos)\b',
  caseSensitive: false,
);

final _genericIncome = RegExp(
  r'\b(?:recibiste|recibid[oa]s?|abono|consignaci[oó]n|dep[oó]sito|ingreso|transferencia\s+recibida|te\s+(?:lleg[oó]|llegaron|enviaron|transfirieron|consignaron|abonaron|depositaron|pag[oó]))\b',
  caseSensitive: false,
);

final _genericExpense = RegExp(
  r'\b(?:compra|compraste|pago|pagaste|retiro|retiraste|transferiste|enviaste|transferencia\s+enviada|d[eé]bito|cargo|consumo|avance)\b',
  caseSensitive: false,
);

// Reminders, promotions and codes: an amount in them is not a movement.
final _genericBlocked = RegExp(
  r'\b(?:vence|vencimiento|recuerda|recu[eé]rdalo|promoci[oó]n|oferta|gana|ganar|sorteo|preaprobad[oa]|c[oó]digo|clave|otp|solicita|paga\s+tu)\b',
  caseSensitive: false,
);

final _genericMerchant = RegExp(
  r'^\s*(?:en|a|de|para)\s+(?<m>.+?)(?=\s+(?:con|desde|usando|tarjeta|TC|TD|T\.|el|en\s+tu|a\s+las|fue|por)\b|[,;]|\.\s|\.?\s*$)',
  caseSensitive: false,
);

/// Reads a notification that no bank template fits, from the words every Colombian bank uses: one amount
/// (`$`, `COP`) and one clear direction (compra, pago, retiro, transferiste... / recibiste, abono...).
/// Returns null unless the movement is clear, so a doubtful text is never guessed.
BankNotice? parseGenericNotice({
  required String title,
  required String content,
  required DateTime receivedAt,
  AmountParser parse = parseLocalizedAmount,
}) {
  final text = _normalize(withoutBalanceClauses('$title. $content'));
  if (text.isEmpty || _genericBlocked.hasMatch(text)) return null;

  final amounts = _genericAmount.allMatches(text).toList();
  final values = {
    for (final m in amounts) parse((m.namedGroup('a') ?? m.namedGroup('b'))!),
  };
  if (values.length != 1) return null;
  final amount = values.single;
  if (amount == null || amount <= 0) return null;

  final income = _genericIncome.hasMatch(text);
  final expense = _genericExpense.hasMatch(text);
  if (income == expense) return null;

  final lower = text.toLowerCase();
  final kind = income
      ? (lower.contains('transfer') || lower.contains('te llegó')
            ? NoticeKind.transferIn
            : NoticeKind.deposit)
      : lower.contains('retir')
      ? NoticeKind.withdrawal
      : lower.contains('transfer') || lower.contains('enviaste')
      ? NoticeKind.transferOut
      : lower.contains('pag')
      ? NoticeKind.payment
      : NoticeKind.purchase;

  final afterAmount = text.substring(amounts.last.end);
  final merchant = _cleanMerchant(
    _genericMerchant.firstMatch(afterAmount)?.namedGroup('m'),
  );
  return BankNotice(
    kind: kind,
    amount: amount.abs(),
    date: _extractDate(text, receivedAt),
    merchant: merchant != null && !_notAMerchant.hasMatch(merchant)
        ? merchant
        : null,
    last4: _last4Pattern.firstMatch(text)?.namedGroup('l'),
  );
}

// «tu cuenta», «la tarjeta *1234», a number or a date are not a shop or a person.
final _notAMerchant = RegExp(
  r'^(?:tu|su|la|el|mi)\b|^(?:cuenta|tarjeta|producto)\b|^\*?\d|\d{4,}',
  caseSensitive: false,
);

/// True when the text may be a money movement (has an amount with `$` or `COP`); used to decide whether an
/// unrecognized notification is worth the AI or the inbox. Promotions and codes usually have no amount.
bool looksFinancial(String title, String content) => RegExp(
  r'\$\s*\d|\d\s*COP\b',
  caseSensitive: false,
).hasMatch('$title $content');
