// From a notification of a bank app to a pending inbox item (T002). Owner: w-avisos.
// Local templates first; when none fits the text is kept as a pending item, and with the AI switch on it waits there
// as «notice to read with AI» (the AI is only called when the user taps the button: see [readWithAi]).
// Nothing here creates a transaction: the user confirms in the review page.
import 'dart:convert';

import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/cards/card_map.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/notifications/bank_apps.dart';
import 'package:monekin/features_ia/notifications/bank_notice.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notice_claims.dart';
import 'package:monekin/features_ia/notifications/notice_redaction.dart';
import 'package:monekin/features_ia/notifications/notification_guards.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// Most calls to the AI to read notices per day, and the shortest wait between two of them.
const kNoticeAiMaxPerDay = 30;
const kNoticeAiMinGap = Duration(seconds: 10);
const _kAiLimitKey = 'ai_notice_calls';

class RawNotice {
  const RawNotice({
    required this.package,
    required this.title,
    required this.content,
    required this.postedAtMs,
    this.id,
  });

  final String package;
  final String title;
  final String content;
  final int postedAtMs;

  /// The id the system gave the notification; with [package] it names the notification across updates.
  final int? id;
}

enum NoticeOutcome {
  /// Not a watched app, empty, or not about money.
  ignored,

  /// Already taken in (the fingerprint was claimed before, maybe by another isolate).
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

/// What happened when the user tapped «Read with AI» on a waiting notice.
enum NoticeReadResult {
  /// The AI read a movement: it is now the proposal of the item.
  read,

  /// The AI said the text is not a money movement.
  notMoney,

  /// The AI answered something that cannot be trusted; the item waits for a manual review.
  unclear,

  /// Today's limit or the minimum wait between two calls was reached; nothing was sent.
  limit,

  /// The AI could not be reached or is not set up; the item is unchanged.
  failed,
}

class NotificationProcessor {
  NotificationProcessor({
    NotificationsPrefs? prefs,
    LocalNotifier? notifier,
    InboxService Function()? inbox,
    NoticeClaims Function()? claims,
    Future<bool> Function()? aiConfigured,
    Future<AiClient> Function()? aiClient,
    Future<String?> Function(String last4)? accountForCard,
    AmountParser? parseAmount,
    DateTime Function()? now,
  }) : prefs = prefs ?? NotificationsPrefs.instance,
       notifier = notifier ?? PluginLocalNotifier.instance,
       _inbox = inbox ?? (() => InboxService.instance),
       _claims = claims ?? (() => DriftNoticeClaims(AppDB.instance)),
       _aiConfigured =
           aiConfigured ?? (() => AiService.instance.isConfigured()),
       _aiClient = aiClient ?? (() => aiClientFor(AiFeature.notice)),
       _accountForCard = accountForCard ?? CardMapService.instance.accountFor,
       _parse = parseAmount ?? parseLocalizedAmount,
       _now = now ?? DateTime.now;

  final NotificationsPrefs prefs;
  final LocalNotifier notifier;
  final InboxService Function() _inbox;
  final NoticeClaims Function() _claims;
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

    final claims = _claims();
    final fp = noticeFingerprint(raw.package, raw.id, raw.title, raw.content);
    if (!await claims.claim(fp, _now())) return NoticeOutcome.duplicate;

    try {
      final posted = DateTime.fromMillisecondsSinceEpoch(raw.postedAtMs);
      ProposedTransaction? proposal;

      // Templates read the original text; what is saved has codes and long numbers masked. The AI gets
      // its own, stricter redaction (see redactForAi), and only when the user taps «Read with AI».
      final text = maskSensitive('${raw.title}\n${raw.content}'.trim());
      String? aiText;

      // Local reading first: the bank templates, then the generic wording every bank uses.
      final notice =
          parseBankNotice(
            title: raw.title,
            content: raw.content,
            receivedAt: posted,
            bank: bankAppFor(raw.package)?.bank,
            parse: _parse,
          ) ??
          parseGenericNotice(
            title: raw.title,
            content: raw.content,
            receivedAt: posted,
            parse: _parse,
          );
      if (notice != null) {
        proposal = await _proposalFrom(notice);
      } else if (await prefs.aiNoticesEnabled()) {
        final sentence = redactForAi('${raw.title}\n${raw.content}');
        if (sentence.isNotEmpty) aiText = sentence;
      }

      final id = await _inbox().addItem(
        InboxDraft(
          source: InboxSource.notification,
          sourceRef: raw.package,
          proposals: proposal == null ? const [] : [proposal],
          rawText: text,
          note: proposal != null
              ? null
              : aiText != null
              ? t.ia_notifications.pending_note_ai_manual
              : t.ia_notifications.pending_note,
          data: aiText == null ? null : {InboxDataKeys.aiText: aiText},
        ),
      );
      await _announce(id);
      return proposal == null
          ? NoticeOutcome.pending
          : NoticeOutcome.recognized;
    } catch (_) {
      await claims.release(fp);
      return NoticeOutcome.failed;
    }
  }

  /// Reads a notice that waits in the inbox («Aviso por leer con IA»): sends exactly the sentence stored in the item
  /// ([InboxDataKeys.aiText]), within the daily limit. The caller has already asked the user to allow notices.
  Future<NoticeReadResult> readWithAi(InboxItem item) async {
    final sentence = item.data?[InboxDataKeys.aiText];
    final inbox = _inbox();
    if (sentence is! String || inbox is! InboxNoticeReading) {
      return NoticeReadResult.failed;
    }
    final ai = await _askAi(sentence, item.createdAt);
    if (ai.limited) return NoticeReadResult.limit;
    final String note;
    final NoticeReadResult result;
    if (ai.proposal != null) {
      note = '';
      result = NoticeReadResult.read;
    } else if (ai.notMoney) {
      note = t.ia_notifications.ai_not_money_note;
      result = NoticeReadResult.notMoney;
    } else if (ai.unclear) {
      note = t.ia_notifications.pending_note_ai;
      result = NoticeReadResult.unclear;
    } else {
      return NoticeReadResult.failed;
    }
    await (inbox as InboxNoticeReading).finishAiNotice(
      item.id,
      proposal: ai.proposal,
      note: note.isEmpty ? null : note,
    );
    return result;
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

  /// [notMoney] is true only when the AI explicitly said the text is not a money movement (promotion,
  /// code...). [unclear] is true when it answered but the answer cannot be trusted (missing or invalid
  /// fields); the notice then waits for the user's review.
  Future<
    ({ProposedTransaction? proposal, bool notMoney, bool unclear, bool limited})
  >
  _askAi(String text, DateTime posted) async {
    const none = (
      proposal: null,
      notMoney: false,
      unclear: false,
      limited: false,
    );
    const limited = (
      proposal: null,
      notMoney: false,
      unclear: false,
      limited: true,
    );
    const unclear = (
      proposal: null,
      notMoney: false,
      unclear: true,
      limited: false,
    );
    try {
      if (!await _aiConfigured()) return none;
      if (!await _reserveAiCall()) return limited;
      final client = await _aiClient();
      final result = await client.chatWithCap([
        const AiMessage.system(
          'You read one Colombian bank notification. Answer one JSON object: '
          '{"is_transaction": bool, "type": "expense"|"income", "amount": string as written in the text, '
          '"merchant": string or null, "date": "dd/mm/yyyy" or null}. '
          'is_transaction is false for promotions, codes, balances and security alerts. Digits other than the amount and the date are hidden.',
        ),
        AiMessage.user(text),
      ], maxTokens: AiTokenCaps.notice);
      final json = result.json();
      final isTransaction = json['is_transaction'];
      if (isTransaction == false) {
        return (proposal: null, notMoney: true, unclear: false, limited: false);
      }
      if (isTransaction != true) return unclear;
      final type = json['type'];
      if (type != 'expense' && type != 'income') return unclear;
      final amount = _parse('${json['amount']}');
      if (amount == null || amount <= 0) return unclear;
      final merchant = json['merchant'] is String
          ? (json['merchant'] as String).trim()
          : null;
      final date = _parseDay('${json['date']}', posted);
      final isIncome = type == 'income';
      final proposal = await _proposalFrom(
        BankNotice(
          kind: isIncome ? NoticeKind.deposit : NoticeKind.purchase,
          amount: amount.abs(),
          date: date,
          merchant: (merchant == null || merchant.isEmpty) ? null : merchant,
        ),
      );
      return (
        proposal: proposal,
        notMoney: false,
        unclear: false,
        limited: false,
      );
    } catch (_) {
      return none;
    }
  }

  /// Counts one AI call in the stored {day, count, lastMs}, shared by every isolate. False when today's
  /// limit is reached or the last call was less than [kNoticeAiMinGap] ago: the notice waits for review.
  Future<bool> _reserveAiCall() => prefs.store.transaction((tx) async {
    final now = _now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    var count = 0;
    var lastMs = 0;
    try {
      final saved = jsonDecode(await tx.get(_kAiLimitKey) ?? '{}') as Map;
      if (saved['day'] == today) {
        count = saved['count'] as int;
        lastMs = saved['lastMs'] as int;
      }
    } catch (_) {
      // An unreadable counter starts the day again.
    }
    final nowMs = now.millisecondsSinceEpoch;
    if (count >= kNoticeAiMaxPerDay ||
        nowMs - lastMs < kNoticeAiMinGap.inMilliseconds) {
      return false;
    }
    await tx.set(
      _kAiLimitKey,
      jsonEncode({'day': today, 'count': count + 1, 'lastMs': nowMs}),
    );
    return true;
  });

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

  /// Generic on purpose: the lock screen must not show anything the bank wrote.
  Future<void> _announce(String itemId) async {
    try {
      await notifier.show(
        id: notificationIdFor(itemId),
        channel: AlertChannel.detected,
        title: kGenericNotificationTitle,
        body: t.ia_notifications.detected_generic,
        payload: '$kInboxPayloadPrefix$itemId',
      );
    } catch (_) {
      // The item is already in the inbox; a failed announcement must not undo it.
    }
  }
}
