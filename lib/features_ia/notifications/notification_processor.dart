// From a notification of a bank app to a pending inbox item (T002). Owner: w-avisos.
// Local templates first; when none fits and the AI is configured, the AI reads the text; otherwise the text
// is kept as a pending item. Nothing here creates a transaction: the user confirms in the review page.
import 'package:intl/intl.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/cards/card_map.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/notifications/bank_apps.dart';
import 'package:monekin/features_ia/notifications/bank_notice.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notification_guards.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class RawNotice {
  const RawNotice({
    required this.package,
    required this.title,
    required this.content,
    required this.postedAtMs,
  });

  final String package;
  final String title;
  final String content;
  final int postedAtMs;
}

enum NoticeOutcome {
  /// Not a watched app, empty, or not about money.
  ignored,

  /// Already seen (same fingerprint).
  duplicate,

  /// Recognized by a local template.
  recognized,

  /// Recognized by the AI.
  recognizedByAi,

  /// Kept as text for manual review.
  pending,

  /// The inbox refused the item; the notice may be processed again.
  failed,
}

class NotificationProcessor {
  NotificationProcessor({
    NotificationsPrefs? prefs,
    LocalNotifier? notifier,
    InboxService Function()? inbox,
    Future<bool> Function()? aiConfigured,
    Future<AiClient> Function()? aiClient,
    Future<String?> Function(String last4)? accountForCard,
    AmountParser? parseAmount,
    DateTime Function()? now,
  }) : prefs = prefs ?? NotificationsPrefs.instance,
       notifier = notifier ?? PluginLocalNotifier.instance,
       _inbox = inbox ?? (() => InboxService.instance),
       _aiConfigured =
           aiConfigured ?? (() => AiService.instance.isConfigured()),
       _aiClient = aiClient ?? (() => AiService.instance.client()),
       _accountForCard = accountForCard ?? CardMapService.instance.accountFor,
       _parse = parseAmount ?? parseLocalizedAmount,
       _now = now ?? DateTime.now;

  final NotificationsPrefs prefs;
  final LocalNotifier notifier;
  final InboxService Function() _inbox;
  final Future<bool> Function() _aiConfigured;
  final Future<AiClient> Function() _aiClient;
  final Future<String?> Function(String last4) _accountForCard;
  final AmountParser _parse;
  final DateTime Function() _now;

  Future<NoticeOutcome> process(RawNotice raw) async {
    if (raw.title.trim().isEmpty && raw.content.trim().isEmpty) {
      return NoticeOutcome.ignored;
    }
    if (!(await prefs.watchedPackages()).contains(raw.package)) {
      return NoticeOutcome.ignored;
    }
    if (!looksFinancial(raw.title, raw.content)) return NoticeOutcome.ignored;

    final fingerprints = NoticeFingerprints(prefs, now: _now);
    final fp = noticeFingerprint(
      raw.package,
      raw.title,
      raw.content,
      raw.postedAtMs,
    );
    if (!await fingerprints.registerIfNew(fp)) return NoticeOutcome.duplicate;

    try {
      final posted = DateTime.fromMillisecondsSinceEpoch(raw.postedAtMs);
      var outcome = NoticeOutcome.recognized;
      ProposedTransaction? proposal;

      final notice = parseBankNotice(
        title: raw.title,
        content: raw.content,
        receivedAt: posted,
        bank: bankAppFor(raw.package)?.bank,
        parse: _parse,
      );
      if (notice != null) {
        proposal = await _proposalFrom(notice);
      } else {
        final ai = await _askAi(raw, posted);
        if (ai.notMoney) return NoticeOutcome.ignored;
        proposal = ai.proposal;
        if (proposal != null) outcome = NoticeOutcome.recognizedByAi;
      }

      final text = '${raw.title}\n${raw.content}'.trim();
      final id = await _inbox().addItem(
        InboxDraft(
          source: InboxSource.notification,
          sourceRef: raw.package,
          proposals: proposal == null ? const [] : [proposal],
          rawText: text,
          note: proposal == null ? t.ia_notifications.pending_note : null,
        ),
      );
      await _announce(id, proposal, text);
      return proposal == null ? NoticeOutcome.pending : outcome;
    } catch (_) {
      await fingerprints.forget(fp);
      return NoticeOutcome.failed;
    }
  }

  Future<ProposedTransaction> _proposalFrom(BankNotice n) async {
    String? accountId;
    if (n.last4 != null) {
      try {
        accountId = await _accountForCard(n.last4!);
      } catch (_) {}
    }
    return ProposedTransaction(
      date: n.date,
      title: n.merchant ?? _kindLabel(n.kind),
      amount: n.amount,
      type: n.type,
      accountId: accountId,
      warning: n.merchant == null
          ? t.ia_notifications.warning_no_merchant
          : null,
    );
  }

  /// [notMoney] is true when the AI said the text is not a money movement (promotion, code...).
  Future<({ProposedTransaction? proposal, bool notMoney})> _askAi(
    RawNotice raw,
    DateTime posted,
  ) async {
    try {
      if (!await _aiConfigured()) return (proposal: null, notMoney: false);
      final client = await _aiClient();
      final result = await client.chat([
        const AiMessage.system(
          'You read one Colombian bank notification. Answer one JSON object: '
          '{"is_transaction": bool, "type": "expense"|"income", "amount": string as written in the text, '
          '"merchant": string or null, "last4": string with the last 4 digits of the card or account or null, '
          '"date": "dd/mm/yyyy" or null}. is_transaction is false for promotions, codes, balances and security alerts.',
        ),
        AiMessage.user('${raw.title}\n${raw.content}'),
      ]);
      final json = result.json();
      if (json['is_transaction'] != true) {
        return (proposal: null, notMoney: true);
      }
      final amount = _parse('${json['amount']}');
      if (amount == null || amount <= 0) {
        return (proposal: null, notMoney: false);
      }
      final merchant = (json['merchant'] as String?)?.trim();
      final last4 = (json['last4'] as String?)?.trim();
      final date = _parseDay('${json['date']}', posted);
      final isIncome = json['type'] == 'income';
      final proposal = await _proposalFrom(
        BankNotice(
          kind: isIncome ? NoticeKind.deposit : NoticeKind.purchase,
          amount: amount.abs(),
          date: date,
          merchant: (merchant == null || merchant.isEmpty) ? null : merchant,
          last4: (last4 != null && RegExp(r'^\d{4}$').hasMatch(last4))
              ? last4
              : null,
        ),
      );
      return (proposal: proposal, notMoney: false);
    } catch (_) {
      return (proposal: null, notMoney: false);
    }
  }

  DateTime _parseDay(String raw, DateTime fallback) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(raw.trim());
    if (m == null) return fallback;
    final d = DateTime(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
      fallback.hour,
      fallback.minute,
    );
    return d.month == int.parse(m.group(2)!) ? d : fallback;
  }

  String _kindLabel(NoticeKind k) {
    final tr = t.ia_notifications;
    return switch (k) {
      NoticeKind.purchase => tr.kind_purchase,
      NoticeKind.payment => tr.kind_payment,
      NoticeKind.transferOut => tr.kind_transfer_out,
      NoticeKind.withdrawal => tr.kind_withdrawal,
      NoticeKind.transferIn => tr.kind_transfer_in,
      NoticeKind.deposit => tr.kind_deposit,
    };
  }

  Future<void> _announce(
    String itemId,
    ProposedTransaction? p,
    String rawText,
  ) async {
    final tr = t.ia_notifications;
    final String body;
    if (p == null) {
      final short = rawText.replaceAll(RegExp(r'\s+'), ' ');
      body = tr.detected_pending(
        text: short.length > 80 ? '${short.substring(0, 80)}…' : short,
      );
    } else {
      final amount = '\$${NumberFormat('#,##0.##', 'es_CO').format(p.amount)}';
      body = p.type == TransactionType.income
          ? tr.detected_income(amount: amount, merchant: p.title)
          : tr.detected_expense(amount: amount, merchant: p.title);
    }
    try {
      await notifier.show(
        id: notificationIdFor(itemId),
        channel: AlertChannel.detected,
        title: 'Finanzas IA',
        body: body,
        payload: '$kInboxPayloadPrefix$itemId',
      );
    } catch (_) {
      // The item is already in the inbox; a failed announcement must not undo it.
    }
  }
}
