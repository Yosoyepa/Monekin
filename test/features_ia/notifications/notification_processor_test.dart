import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';

import 'test_support.dart';

class _FakeAiClient implements AiClient {
  _FakeAiClient(this.answer, {this.fail = false});

  final String answer;
  final bool fail;
  int calls = 0;

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls++;
    if (fail) throw const AiException(AiErrorKind.network, 'offline');
    return AiResult(text: answer);
  }

  @override
  Future<List<String>> listModels() async => const [];
}

const _nequi = 'com.nequi.MobileApp';
final _postedMs = DateTime(2026, 11, 4, 10, 15).millisecondsSinceEpoch;

void main() {
  late FakeInbox inbox;
  late FakeNotifier notifier;
  late NotificationsPrefs prefs;

  NotificationProcessor build({
    _FakeAiClient? ai,
    Map<String, String> cards = const {},
  }) => NotificationProcessor(
    prefs: prefs,
    notifier: notifier,
    inbox: () => inbox,
    aiConfigured: () async => ai != null,
    aiClient: () async => ai!,
    accountForCard: (last4) async => cards[last4],
    parseAmount: testAmountParser,
    now: () => DateTime(2026, 11, 4, 10, 16),
  );

  RawNotice notice(
    String content, {
    String package = _nequi,
    String title = 'Nequi',
    int? at,
  }) => RawNotice(
    package: package,
    title: title,
    content: content,
    postedAtMs: at ?? _postedMs,
  );

  setUp(() {
    inbox = FakeInbox();
    notifier = FakeNotifier();
    prefs = NotificationsPrefs(MemoryKeyValueStore());
  });

  test('a recognized notice goes to the inbox and is announced', () async {
    final outcome = await build().process(notice('Pagaste \$45.900 en EXITO'));

    expect(outcome, NoticeOutcome.recognized);
    expect(inbox.drafts, hasLength(1));
    final draft = inbox.drafts.single;
    expect(draft.source, InboxSource.notification);
    expect(draft.sourceRef, _nequi);
    expect(draft.rawText, contains('Pagaste'));
    final row = draft.proposals.single;
    expect(row.title, 'EXITO');
    expect(row.amount, 45900);
    expect(row.type, TransactionType.expense);
    expect(row.warning, isNull);

    final shown = notifier.shown.single;
    expect(shown.channel, AlertChannel.detected);
    expect(shown.payload, 'inbox:item-1');
    expect(shown.body, 'New expense detected: \$45.900 EXITO — tap to review');
  });

  test('income is announced as income', () async {
    await build().process(notice('Juan Pérez te envió \$300.000'));
    expect(inbox.drafts.single.proposals.single.type, TransactionType.income);
    expect(
      notifier.shown.single.body,
      'New income detected: \$300.000 Juan Pérez — tap to review',
    );
  });

  test('the account comes from the card map by last four digits', () async {
    await build(cards: {'1234': 'acc-1'}).process(
      notice(
        'Compraste \$32.500,00 en UBER RIDES con tu T.Deb *1234, el 15/09/2026 a las 20:35.',
        package: 'co.com.bancolombia.personas.superapp',
        title: 'Bancolombia',
      ),
    );
    final row = inbox.drafts.single.proposals.single;
    expect(row.accountId, 'acc-1');
    expect(row.date, DateTime(2026, 9, 15, 20, 35));
  });

  test('a missing merchant is flagged for the review', () async {
    await build().process(notice('Recibiste \$75.000'));
    final deposit = inbox.drafts.single.proposals.single;
    expect(deposit.title, 'Deposit');
    expect(deposit.warning, isNotNull);

    await build().process(
      notice(
        'Transferencia recibida por \$450.000',
        package: 'com.bancodebogota.bancamovil',
      ),
    );
    final transfer = inbox.drafts.last.proposals.single;
    expect(transfer.title, 'Transfer received');
    expect(transfer.warning, isNotNull);
  });

  test('the same notice twice creates one item and one announcement', () async {
    final p = build();
    expect(
      await p.process(notice('Pagaste \$45.900 en EXITO')),
      NoticeOutcome.recognized,
    );
    expect(
      await p.process(
        notice('Pagaste \$45.900 en EXITO', at: _postedMs + 20000),
      ),
      NoticeOutcome.duplicate,
    );
    expect(inbox.drafts, hasLength(1));
    expect(notifier.shown, hasLength(1));
  });

  test('two equal purchases a minute apart are two items', () async {
    final p = build();
    await p.process(notice('Pagaste \$45.900 en EXITO'));
    await p.process(notice('Pagaste \$45.900 en EXITO', at: _postedMs + 61000));
    expect(inbox.drafts, hasLength(2));
  });

  test('an app that is not watched is ignored', () async {
    final outcome = await build().process(
      notice('Pagaste \$45.900 en EXITO', package: 'com.whatsapp'),
    );
    expect(outcome, NoticeOutcome.ignored);
    expect(inbox.drafts, isEmpty);
  });

  test('an app added by hand is read', () async {
    await prefs.setWatchedPackages({'com.mi.banco'});
    final outcome = await build().process(
      notice('Pagaste \$45.900 en EXITO', package: 'com.mi.banco'),
    );
    expect(outcome, NoticeOutcome.recognized);
  });

  test('a promotion without an amount is ignored', () async {
    final ai = _FakeAiClient('{}');
    final outcome = await build(
      ai: ai,
    ).process(notice('Haz 5 compras con tu Tarjeta Nequi Visa y gana premios'));
    expect(outcome, NoticeOutcome.ignored);
    expect(ai.calls, 0);
  });

  group('unknown text', () {
    const unknown =
        'Movimiento en tu cuenta: débito por \$88.500 en TIENDA XYZ el 03/11/2026';

    test('the AI reads it when it is configured', () async {
      final ai = _FakeAiClient(
        '{"is_transaction": true, "type": "expense", "amount": "88.500", "merchant": "TIENDA XYZ", "last4": "4321", "date": "03/11/2026"}',
      );
      final outcome = await build(
        ai: ai,
        cards: {'4321': 'acc-9'},
      ).process(notice(unknown));

      expect(outcome, NoticeOutcome.recognizedByAi);
      expect(ai.calls, 1);
      final row = inbox.drafts.single.proposals.single;
      expect(row.amount, 88500);
      expect(row.title, 'TIENDA XYZ');
      expect(row.accountId, 'acc-9');
      expect(row.date, DateTime(2026, 11, 3, 10, 15));
      expect(notifier.shown, hasLength(1));
    });

    test('an amount the AI invented in a bad format is not trusted', () async {
      final ai = _FakeAiClient(
        '{"is_transaction": true, "type": "expense", "amount": "mucho", "merchant": "X"}',
      );
      expect(
        await build(ai: ai).process(notice(unknown)),
        NoticeOutcome.pending,
      );
    });

    test(
      'when the AI says it is not a movement the notice is dropped',
      () async {
        final ai = _FakeAiClient('{"is_transaction": false}');
        expect(
          await build(ai: ai).process(notice(unknown)),
          NoticeOutcome.ignored,
        );
        expect(inbox.drafts, isEmpty);
      },
    );

    test('without AI the text waits as a pending item', () async {
      final outcome = await build().process(notice(unknown));

      expect(outcome, NoticeOutcome.pending);
      final draft = inbox.drafts.single;
      expect(draft.proposals, isEmpty);
      expect(draft.rawText, contains('TIENDA XYZ'));
      expect(draft.note, isNotNull);
      expect(notifier.shown.single.body, startsWith('Bank notice to review: '));
    });

    test('when the AI fails the text waits as a pending item', () async {
      final outcome = await build(
        ai: _FakeAiClient('', fail: true),
      ).process(notice(unknown));
      expect(outcome, NoticeOutcome.pending);
      expect(inbox.drafts.single.rawText, contains('TIENDA XYZ'));
    });

    test('a template match does not spend an AI call', () async {
      final ai = _FakeAiClient('{}');
      await build(ai: ai).process(notice('Pagaste \$45.900 en EXITO'));
      expect(ai.calls, 0);
    });
  });

  test('if the inbox fails the notice can be processed again', () async {
    final p = build();
    inbox.failNext = true;
    expect(
      await p.process(notice('Pagaste \$45.900 en EXITO')),
      NoticeOutcome.failed,
    );
    expect(notifier.shown, isEmpty);

    expect(
      await p.process(notice('Pagaste \$45.900 en EXITO')),
      NoticeOutcome.recognized,
    );
    expect(inbox.drafts, hasLength(1));
  });
}
