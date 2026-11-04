import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';
import 'package:monekin/features_ia/notifications/notifications_background.dart';
import 'package:monekin/features_ia/notifications/notifications_feature.dart';
import 'package:notification_listener_service/notification_event.dart';

import 'test_support.dart';

class _SpyAi implements AiClient {
  int calls = 0;

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls++;
    return const AiResult(text: '{"is_transaction": false}');
  }

  @override
  Future<List<String>> listModels() async => const [];
}

const _nequi = 'com.nequi.MobileApp';
const _stranger = 'com.example.whatsapp';
final _postedMs = DateTime(2026, 11, 4, 10, 15).millisecondsSinceEpoch;

ServiceNotificationEvent _event(
  String package,
  String content, {
  String title = 'Aviso',
  bool removed = false,
  bool ongoing = false,
}) => ServiceNotificationEvent(
  id: 1,
  title: title,
  canReply: false,
  haveExtraPicture: false,
  hasRemoved: removed,
  packageName: package,
  content: content,
  onGoing: ongoing,
  timestamp: _postedMs,
  appIcon: null,
  extrasPicture: null,
  largeIcon: null,
);

Map<String, Object?> _active(String package, String content) => {
  'id': 1,
  'packageName': package,
  'title': 'Aviso',
  'content': content,
  'postTime': _postedMs,
  'onGoing': false,
};

void main() {
  late FakeInbox inbox;
  late FakeNotifier notifier;
  late NotificationsPrefs prefs;
  late _SpyAi ai;
  late NotificationProcessor processor;
  late List<String> logged;
  late DebugPrintCallback originalDebugPrint;

  setUp(() async {
    inbox = FakeInbox();
    notifier = FakeNotifier();
    prefs = NotificationsPrefs(MemoryKeyValueStore());
    // With the AI switch on, a foreign or forged notice that got through would reach the AI.
    await prefs.setAiNoticesEnabled(true);
    ai = _SpyAi();
    processor = NotificationProcessor(
      prefs: prefs,
      notifier: notifier,
      inbox: () => inbox,
      aiConfigured: () async => true,
      aiClient: () async => ai,
      accountForCard: (_) async => null,
      parseAmount: testAmountParser,
      now: () => DateTime(2026, 11, 4, 10, 16),
    );
    logged = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
  });

  tearDown(() => debugPrint = originalDebugPrint);

  group('F-08: a forged listener event does not enter', () {
    test(
      'an event whose notice is not among the active ones is ignored',
      () async {
        await handleListenerEvent(
          _event(_nequi, 'Pagaste \$10.000 en TIENDA PRUEBA'),
          processor: processor,
          readActive: () async => const [],
        );

        expect(inbox.drafts, isEmpty);
        expect(notifier.shown, isEmpty);
        expect(ai.calls, 0);
        expect(await prefs.fingerprints(), isEmpty);
      },
    );

    test('only what the system lists as active is processed', () async {
      await handleListenerEvent(
        _event(_nequi, 'Pagaste \$10.000 en TIENDA FALSA'),
        processor: processor,
        readActive: () async => [_active(_nequi, 'Pagaste \$45.900 en EXITO')],
      );

      expect(inbox.drafts, hasLength(1));
      final draft = inbox.drafts.single;
      expect(draft.rawText, contains('EXITO'));
      expect(draft.rawText, isNot(contains('FALSA')));
      expect(draft.proposals.single.amount, 45900);
    });

    test('a removed notification does not even read the active list', () async {
      var reads = 0;
      await handleListenerEvent(
        _event(_nequi, 'Pagaste \$45.900 en EXITO', removed: true),
        processor: processor,
        readActive: () async {
          reads++;
          return [_active(_nequi, 'Pagaste \$45.900 en EXITO')];
        },
      );
      expect(reads, 0);
      expect(inbox.drafts, isEmpty);
    });
  });

  test('a burst of events shares one more read of the active list', () async {
    var reads = 0;
    final release = Completer<void>();
    Future<List<dynamic>> slowRead() async {
      reads++;
      await release.future;
      return const [];
    }

    final events = [
      for (var i = 0; i < 20; i++)
        handleListenerEvent(
          _event(_nequi, 'x $i'),
          processor: processor,
          readActive: slowRead,
        ),
    ];
    release.complete();
    await Future.wait(events);
    expect(reads, 2);
  });

  group('notices of apps that are not watched', () {
    const text = 'Tu código es 482913. Pagaste \$45.900 en EXITO';

    void expectNothingLeft() {
      expect(inbox.drafts, isEmpty);
      expect(notifier.shown, isEmpty);
      expect(ai.calls, 0);
      expect(logged.where((l) => l.contains('482913')), isEmpty);
    }

    test(
      'the live stream drops them before saving, recording or sending',
      () async {
        await handleListenerEvent(
          _event(_stranger, text),
          processor: processor,
          readActive: () async => [_active(_stranger, text)],
        );
        expectNothingLeft();
        expect(await prefs.fingerprints(), isEmpty);
      },
    );

    test('the periodic scan drops them', () async {
      await processActiveNotices(
        processor: processor,
        readActive: () async => [_active(_stranger, text)],
      );
      expectNothingLeft();
      expect(await prefs.fingerprints(), isEmpty);
    });

    test('what the plugin reads from the shade is dropped', () async {
      await processActiveNotices(
        processor: processor,
        readActive: () async => [
          _active(_stranger, text),
          _active('com.google.android.apps.messaging', 'Hola, nos vemos'),
          _active('com.example.otp', 'Tu clave es 111222'),
        ],
      );
      expectNothingLeft();
      expect(await prefs.fingerprints(), isEmpty);
    });
  });
}
