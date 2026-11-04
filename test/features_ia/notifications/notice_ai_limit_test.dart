// F-07: the AI that reads bank notices is limited to 30 calls a day and one every 10 seconds.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
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

  NotificationProcessor build() => NotificationProcessor(
    prefs: prefs,
    notifier: FakeNotifier(),
    inbox: () => inbox,
    aiConfigured: () async => true,
    aiClient: () async => client,
    accountForCard: (_) async => null,
    parseAmount: testAmountParser,
    now: () => now,
  );

  var counter = 0;
  Future<NoticeOutcome> send() => build().process(
    RawNotice(
      package: 'com.nequi.MobileApp',
      title: 'Nequi',
      // The wording is not one the local templates know, so the AI is asked.
      content: 'Movimiento raro numero ${counter++} por \$10.000 en TIENDA',
      postedAtMs: now.millisecondsSinceEpoch,
    ),
  );

  setUp(() async {
    inbox = FakeInbox();
    client = _Client();
    counter = 0;
    now = DateTime(2026, 11, 4, 10, 0);
    prefs = NotificationsPrefs(MemoryKeyValueStore());
    await prefs.setAiNoticesEnabled(true);
  });

  test(
    'a second notice within 10 seconds waits for review without a call',
    () async {
      expect(await send(), NoticeOutcome.recognizedByAi);
      now = now.add(const Duration(seconds: 9));

      expect(await send(), NoticeOutcome.pending);

      expect(client.sent, hasLength(1));
      expect(inbox.drafts.last.proposals, isEmpty);
      now = now.add(const Duration(seconds: 2));
      expect(await send(), NoticeOutcome.recognizedByAi);
      expect(client.sent, hasLength(2));
    },
  );

  test(
    'after 30 calls in a day the notice waits for review without a call',
    () async {
      for (var i = 0; i < kNoticeAiMaxPerDay; i++) {
        expect(await send(), NoticeOutcome.recognizedByAi, reason: 'call $i');
        now = now.add(const Duration(seconds: 11));
      }

      expect(await send(), NoticeOutcome.pending);

      expect(client.sent, hasLength(kNoticeAiMaxPerDay));
      expect(inbox.drafts.last.proposals, isEmpty);
    },
  );

  test(
    'the count survives a new processor and starts again the next day',
    () async {
      for (var i = 0; i < kNoticeAiMaxPerDay; i++) {
        await send();
        now = now.add(const Duration(seconds: 11));
      }
      expect(await send(), NoticeOutcome.pending);

      now = DateTime(2026, 11, 5, 8, 0);

      expect(await send(), NoticeOutcome.recognizedByAi);
      expect(client.sent, hasLength(kNoticeAiMaxPerDay + 1));
    },
  );
}
