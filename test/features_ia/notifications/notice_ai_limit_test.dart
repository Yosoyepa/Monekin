// F-07: the AI that reads bank notices is limited to 30 calls a day and one every 10 seconds.
// Round 3: it only runs when the user taps «Read with AI», so the limit is checked there.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/notifications/notice_claims.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';

import 'test_support.dart';

class _Client implements AiClient {
  final List<String> sent = [];

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    sent.add(messages.last.text);
    return AiResult(
      text: jsonEncode({
        'is_transaction': true,
        'type': 'expense',
        'amount': '10.000',
        'merchant': 'TIENDA',
        'date': null,
      }),
    );
  }

  @override
  Future<List<String>> listModels() async => const [];
}

void main() {
  late FakeInbox inbox;
  late NotificationsPrefs prefs;
  late _Client client;
  late DateTime now;
  late MemoryNoticeClaims claims;

  NotificationProcessor build() => NotificationProcessor(
    prefs: prefs,
    notifier: FakeNotifier(),
    inbox: () => inbox,
    claims: () => claims,
    aiConfigured: () async => true,
    aiClient: () async => client,
    accountForCard: (_) async => null,
    parseAmount: testAmountParser,
    now: () => now,
  );

  var counter = 0;

  /// A notice the local templates do not know: it waits in the inbox, then the user taps «Read with AI».
  Future<NoticeReadResult> read() async {
    final outcome = await build().process(
      RawNotice(
        package: 'com.nequi.MobileApp',
        title: 'Nequi',
        content: 'Movimiento raro numero ${counter++} por \$10.000 en TIENDA',
        postedAtMs: now.millisecondsSinceEpoch,
      ),
    );
    expect(outcome, NoticeOutcome.pending);
    return build().readWithAi(itemOfDraft('item-$counter', inbox.drafts.last));
  }

  setUp(() async {
    inbox = FakeInbox();
    claims = MemoryNoticeClaims();
    client = _Client();
    counter = 0;
    now = DateTime(2026, 11, 4, 10, 0);
    prefs = NotificationsPrefs(MemoryKeyValueStore());
    await prefs.setAiNoticesEnabled(true);
  });

  test(
    'a second read within 10 seconds waits for the user without a call',
    () async {
      expect(await read(), NoticeReadResult.read);
      now = now.add(const Duration(seconds: 9));

      expect(await read(), NoticeReadResult.limit);

      expect(client.sent, hasLength(1));
      expect(inbox.finished, hasLength(1));
      now = now.add(const Duration(seconds: 2));
      expect(await read(), NoticeReadResult.read);
      expect(client.sent, hasLength(2));
    },
  );

  test(
    'after 30 calls in a day the notice waits for review without a call',
    () async {
      for (var i = 0; i < kNoticeAiMaxPerDay; i++) {
        expect(await read(), NoticeReadResult.read, reason: 'call $i');
        now = now.add(const Duration(seconds: 11));
      }

      expect(await read(), NoticeReadResult.limit);

      expect(client.sent, hasLength(kNoticeAiMaxPerDay));
      expect(inbox.finished, hasLength(kNoticeAiMaxPerDay));
    },
  );

  test(
    'the count survives a new processor and starts again the next day',
    () async {
      for (var i = 0; i < kNoticeAiMaxPerDay; i++) {
        await read();
        now = now.add(const Duration(seconds: 11));
      }
      expect(await read(), NoticeReadResult.limit);

      now = DateTime(2026, 11, 5, 8, 0);

      expect(await read(), NoticeReadResult.read);
      expect(client.sent, hasLength(kNoticeAiMaxPerDay + 1));
    },
  );
}
