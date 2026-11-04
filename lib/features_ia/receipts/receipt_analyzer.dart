// Prompt, parsing and validation of a receipt read by the AI (T002). Owner: w-recibos.
// The AI client, catalog, card lookup and amount parser are injected so tests run with fakes.
import 'dart:typed_data';

import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/cards/card_map.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/core/privacy/image_metadata.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';

/// User-facing texts the analyzer writes into the proposal and the inbox note.
class ReceiptMessages {
  const ReceiptMessages({
    this.defaultTitle = 'Receipt',
    this.missingDate = 'The date was not read; today was used',
    this.missingMerchant = 'The merchant was not read',
    this.missingTotal = 'The total was not read',
    this.aiError = defaultAiError,
    this.unsupportedImage = 'Only JPEG and PNG photos can be read',
  });

  final String defaultTitle;
  final String missingDate;
  final String missingMerchant;
  final String missingTotal;

  /// Text for a photo that is not a JPEG or PNG and could not be converted.
  final String unsupportedImage;

  /// Text for an AI failure; the receipt is kept in the inbox with this note.
  final String Function(AiErrorKind kind) aiError;

  static String defaultAiError(AiErrorKind kind) => switch (kind) {
    AiErrorKind.notConfigured => 'AI is not configured',
    AiErrorKind.invalidKey => 'The API key was rejected',
    AiErrorKind.quotaExceeded => 'The AI quota is exhausted',
    AiErrorKind.network => 'No connection to the AI provider',
    AiErrorKind.timeout => 'The AI took too long to answer',
    AiErrorKind.badResponse => 'The AI answered something unreadable',
    AiErrorKind.unknown => 'The AI failed',
  };
}

const _rules = '''
You read one purchase receipt from Colombia and answer ONE JSON object. Rules:
- Amounts use a dot for thousands and a comma for decimals: "45.900" is forty-five thousand nine hundred, "12,50" is twelve and a half.
- Dates are dd/mm/yyyy (day first). Answer the date as yyyy-mm-dd.
- "total" is the final TOTAL printed on the receipt (what was paid), in pesos, as a number without separators (45900). Use the printed total even if subtotal + VAT (IVA) differs by rounding.
- A suggested tip ("propina sugerida") is NOT part of the total unless the receipt says it was charged. Never add it.
- Delivery fee (domicilio) and VAT are already inside the total. Return ONE transaction per receipt, never one per line.
- "merchant" is the name of the shop or restaurant.
- "category_id" must be one of the expense category ids of the catalog, or null if none fits.
- "card_last4" are the last 4 digits of the card used, if the receipt shows them (e.g. "****1234"), else null. Never answer a full card number.
- "warning" is a short sentence in Spanish for the user if something is unclear (blurry total, cropped image), else null.
Answer exactly: {"date":"yyyy-mm-dd","merchant":"","total":0,"category_id":null,"card_last4":null,"warning":null}
No text outside the JSON.''';

/// Builds the system + user messages for one receipt photo. [categoriesJson] is the only data of the user it carries:
/// the account comes from the card digits the receipt prints, matched on the phone.
List<AiMessage> buildReceiptMessages({
  required String categoriesJson,
  required Uint8List imageBytes,
  required DateTime today,
}) {
  final system = [
    _rules,
    'Expense categories of the user (use only these ids):\n$categoriesJson',
    'Today is ${_isoDate(today)}.',
  ].join('\n\n');
  return [
    AiMessage.system(system),
    AiMessage.user('Read this receipt.', images: [AiImage(bytes: imageBytes)]),
  ];
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(Object? raw) {
  if (raw is! String) return null;
  final s = raw.trim();
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (iso != null) {
    return _validDate(
      int.parse(iso[1]!),
      int.parse(iso[2]!),
      int.parse(iso[3]!),
    );
  }
  final dmy = RegExp(
    r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2}|\d{4})$',
  ).firstMatch(s);
  if (dmy != null) {
    var year = int.parse(dmy[3]!);
    if (year < 100) year += 2000;
    return _validDate(year, int.parse(dmy[2]!), int.parse(dmy[1]!));
  }
  return null;
}

DateTime? _validDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, m, d);
  return date.month == m && date.day == d ? date : null;
}

double? _parseTotal(Object? raw, double? Function(String) parseAmount) {
  final value = switch (raw) {
    num n => n.toDouble(),
    String s => parseAmount(s),
    _ => null,
  };
  return value != null && value.isFinite && value > 0 ? value : null;
}

String? _cleanLast4(Object? raw) {
  if (raw == null) return null;
  final digits = raw.toString().replaceAll(RegExp(r'\D'), '');
  return digits.length >= 4 ? digits.substring(digits.length - 4) : null;
}

String? _text(Object? raw) {
  if (raw is! String) return null;
  final s = raw.trim();
  return s.isEmpty || s.toLowerCase() == 'null' ? null : s;
}

/// Turns the AI answer into one validated proposal, or null when no valid total could be read.
/// Ids missing from [catalog] become null; the account comes from the card map when the last 4 match, never from the model.
Future<ProposedTransaction?> parseReceiptResponse(
  Map<String, dynamic> json, {
  required AiCatalog catalog,
  required Future<String?> Function(String last4) accountForLast4,
  required double? Function(String) parseAmount,
  required DateTime now,
  ReceiptMessages messages = const ReceiptMessages(),
}) async {
  final total = _parseTotal(json['total'], parseAmount);
  if (total == null) return null;

  final warnings = <String>[];
  final date = _parseDate(json['date']);
  if (date == null) warnings.add(messages.missingDate);
  final merchant = _text(json['merchant']);
  if (merchant == null) warnings.add(messages.missingMerchant);
  final modelWarning = _text(json['warning']);
  if (modelWarning != null) warnings.add(modelWarning);

  final categoryId = _text(json['category_id']);
  final validCategory =
      categoryId != null &&
      catalog.categories.any((c) => c.id == categoryId && c.type == 'E');

  final accountIds = catalog.accounts.map((a) => a.id).toSet();
  String? accountId;
  final last4 = _cleanLast4(json['card_last4']);
  if (last4 != null) {
    final mapped = await accountForLast4(last4);
    if (mapped != null && accountIds.contains(mapped)) accountId = mapped;
  }

  return ProposedTransaction(
    date: date ?? DateTime(now.year, now.month, now.day),
    title: merchant ?? messages.defaultTitle,
    amount: total,
    type: TransactionType.expense,
    categoryId: validCategory ? categoryId : null,
    accountId: accountId,
    warning: warnings.isEmpty ? null : warnings.join(' · '),
  );
}

/// Reads one receipt photo and builds the [InboxDraft]. Never throws for AI failures:
/// the draft then has no proposal and carries the error in [InboxDraft.note].
class ReceiptAnalyzer {
  ReceiptAnalyzer({
    Future<AiClient> Function()? clientProvider,
    Future<AiCatalog> Function()? catalogLoader,
    Future<String?> Function(String last4)? accountForLast4,
    double? Function(String)? parseAmount,
    DateTime Function()? now,
    this.messages = const ReceiptMessages(),
  }) : _clientProvider = clientProvider ?? (() => AiService.instance.client()),
       _catalogLoader = catalogLoader ?? loadAiCatalog,
       _accountForLast4 = accountForLast4 ?? CardMapService.instance.accountFor,
       _parseAmount = parseAmount ?? parseLocalizedAmount,
       _now = now ?? DateTime.now;

  final Future<AiClient> Function() _clientProvider;
  final Future<AiCatalog> Function() _catalogLoader;
  final Future<String?> Function(String last4) _accountForLast4;
  final double? Function(String) _parseAmount;
  final DateTime Function() _now;
  final ReceiptMessages messages;

  Future<InboxDraft> analyze({
    required Uint8List imageBytes,
    required String filePath,
    required String fileName,
  }) async {
    InboxDraft draft(List<ProposedTransaction> proposals, {String? note}) =>
        InboxDraft(
          source: InboxSource.receipt,
          sourceRef: fileName,
          proposals: proposals,
          attachmentPaths: [filePath],
          note: note,
        );

    try {
      final safeImage = await normalizeImage(imageBytes);
      final catalog = await _catalogLoader();
      final client = await _clientProvider();
      final result = await client.chatWithCap(
        buildReceiptMessages(
          categoriesJson: catalog.categoriesForPrompt(types: {'E'}),
          imageBytes: safeImage,
          today: _now(),
        ),
        maxTokens: AiTokenCaps.receipt,
      );
      final proposal = await parseReceiptResponse(
        result.json(),
        catalog: catalog,
        accountForLast4: _accountForLast4,
        parseAmount: _parseAmount,
        now: _now(),
        messages: messages,
      );
      if (proposal == null) return draft(const [], note: messages.missingTotal);
      return draft([proposal]);
    } on UnsupportedImageException {
      return draft(const [], note: messages.unsupportedImage);
    } on AiException catch (e) {
      return draft(const [], note: messages.aiError(e.kind));
    } catch (_) {
      return draft(const [], note: messages.aiError(AiErrorKind.badResponse));
    }
  }
}
