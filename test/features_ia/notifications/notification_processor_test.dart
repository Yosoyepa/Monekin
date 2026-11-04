import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notice_claims.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import 'test_support.dart';

class _FakeAiClient implements AiClient {
  _FakeAiClient(this.answer, {this.fail = false});

  final String answer;
  final bool fail;
  int calls = 0;
  final List<AiMessage> sent = [];

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls++;
    sent.addAll(messages);
    if (fail) throw const AiException(AiErrorKind.network, 'offline');
    return AiResult(text: answer);
  }

  @override
  Future<List<String>> listModels() async => const [];
}

/// Records the `max_tokens` each request asked for.
class _CappedAiClient extends _FakeAiClient implements AiCappedClient {
  _CappedAiClient(super.answer);

  final requests = <int>[];

  @override
  Future<AiResult> chatCapped(
    List<AiMessage> messages, {
    required int? maxTokens,
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) {
    requests.add(maxTokens!);
    return chat(messages, jsonOutput: jsonOutput, timeout: timeout);
  }
}

const _nequi = 'com.nequi.MobileApp';
final _postedMs = DateTime(2026, 11, 4, 10, 15).millisecondsSinceEpoch;

void main() {
  late FakeInbox inbox;
  late FakeNotifier notifier;
  late NotificationsPrefs prefs;
  late MemoryNoticeClaims claims;

  NotificationProcessor build({
    _FakeAiClient? ai,
    Map<String, String> cards = const {},
  }) => NotificationProcessor(
    prefs: prefs,
    notifier: notifier,
    inbox: () => inbox,
    claims: () => claims,
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
    int? id,
  }) => RawNotice(
    package: package,
    title: title,
    content: content,
    postedAtMs: at ?? _postedMs,
    id: id,
  );

  setUp(() {
    claims = MemoryNoticeClaims();
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
    expect(shown.body, 'New movement to review');
  });

  test('income is read as income', () async {
    await build().process(notice('Juan Pérez te envió \$300.000'));
    expect(inbox.drafts.single.proposals.single.type, TransactionType.income);
  });

  test('the local notification carries nothing the bank wrote', () async {
    final p = build();
    await p.process(notice('Pagaste \$45.900 en EXITO'));
    await p.process(
      notice(
        'Movimiento en tu cuenta: débito por \$88.500 en TIENDA XYZ',
        at: _postedMs + 120000,
      ),
    );
    expect(notifier.shown, hasLength(2));
    for (final n in notifier.shown) {
      expect(n.title, 'Finanzas IA');
      expect(n.body, 'New movement to review');
    }
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

  test('the same notice delivered again later is still one item', () async {
    final p = build();
    await p.process(notice('Pagaste \$45.900 en EXITO', id: 7));
    final again = await p.process(
      notice('  PAGASTE \$45.900 en exito ', id: 7, at: _postedMs + 61000),
    );
    expect(again, NoticeOutcome.duplicate);
    expect(inbox.drafts, hasLength(1));
  });

  test(
    'two equal texts under different notification ids are two items',
    () async {
      final p = build();
      await p.process(notice('Pagaste \$45.900 en EXITO', id: 7));
      await p.process(notice('Pagaste \$45.900 en EXITO', id: 8));
      expect(inbox.drafts, hasLength(2));
    },
  );

  test(
    'a claim is dropped after 30 days, so the same text counts again',
    () async {
      var now = DateTime(2026, 11, 4, 10, 16);
      final p = NotificationProcessor(
        prefs: prefs,
        notifier: notifier,
        inbox: () => inbox,
        claims: () => claims,
        aiConfigured: () async => false,
        accountForCard: (_) async => null,
        parseAmount: testAmountParser,
        now: () => now,
      );
      await p.process(notice('Pagaste \$45.900 en EXITO', id: 7));
      now = now.add(const Duration(days: 29));
      expect(
        await p.process(notice('Pagaste \$45.900 en EXITO', id: 7)),
        NoticeOutcome.duplicate,
      );
      now = now.add(const Duration(days: 2));
      expect(
        await p.process(notice('Pagaste \$45.900 en EXITO', id: 7)),
        NoticeOutcome.recognized,
      );
      expect(inbox.drafts, hasLength(2));
    },
  );

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

  // F-07. Every text in this group is synthetic: none is a real notice.
  group('local reading without the AI', () {
    // Wording that no bank template covers; the generic reader has to get amount, direction and merchant.
    final samples = <({String text, double amount, bool income, String? who})>[
      (
        text: 'Débito por \$88.500 en TIENDA XYZ el 03/11/2026',
        amount: 88500,
        income: false,
        who: 'TIENDA XYZ',
      ),
      (
        text: 'Se realizó un pago de \$1.250.000 a ARRIENDO LOS PINOS',
        amount: 1250000,
        income: false,
        who: 'ARRIENDO LOS PINOS',
      ),
      (
        text: 'Retiro en cajero por \$300.000 COP',
        amount: 300000,
        income: false,
        who: null,
      ),
      (
        text: 'Consignación recibida por \$2.000.000 COP de CARLOS GOMEZ',
        amount: 2000000,
        income: true,
        who: 'CARLOS GOMEZ',
      ),
      (
        text: 'Recibiste una transferencia de \$150.000 de Ana Torres',
        amount: 150000,
        income: true,
        who: 'Ana Torres',
      ),
      (
        text: 'Pagaste la factura de energía por \$230.400 COP',
        amount: 230400,
        income: false,
        who: null,
      ),
      (
        text:
            'Tu tarjeta terminada en 4321 registró un consumo por \$45.000 en FARMACIA CENTRO',
        amount: 45000,
        income: false,
        who: 'FARMACIA CENTRO',
      ),
      (
        text: 'Transferencia enviada: \$75.000 COP a Laura Pérez',
        amount: 75000,
        income: false,
        who: 'Laura Pérez',
      ),
      (
        text: 'Abono de nómina por \$3.800.000 COP',
        amount: 3800000,
        income: true,
        who: null,
      ),
      (
        text: 'Pago PSE por \$89.900 a NETFLIX COLOMBIA',
        amount: 89900,
        income: false,
        who: 'NETFLIX COLOMBIA',
      ),
      (
        text:
            'Cargo automático de \$34.900 en SPOTIFY el 05/11/2026 a las 08:15',
        amount: 34900,
        income: false,
        who: 'SPOTIFY',
      ),
    ];

    for (final s in samples) {
      test('reads «${s.text}» without the AI', () async {
        final ai = _FakeAiClient('{}');
        await prefs.setAiNoticesEnabled(true);
        final outcome = await build(ai: ai).process(notice(s.text));

        expect(outcome, NoticeOutcome.recognized);
        expect(ai.calls, 0);
        final row = inbox.drafts.single.proposals.single;
        expect(row.amount, s.amount);
        expect(
          row.type,
          s.income ? TransactionType.income : TransactionType.expense,
        );
        if (s.who != null) expect(row.title, s.who);
        expect(row.warning == null, s.who != null);
      });
    }

    test('the date of the text is kept', () async {
      await build().process(notice(samples.first.text));
      expect(
        inbox.drafts.single.proposals.single.date,
        DateTime(2026, 11, 3, 10, 15),
      );
    });

    test('the last 4 digits find the account', () async {
      await build(cards: {'4321': 'acc-4'}).process(notice(samples[6].text));
      expect(inbox.drafts.single.proposals.single.accountId, 'acc-4');
    });

    for (final text in [
      'Tu saldo disponible es \$15.430.200,00',
      'Tu pago de \$120.000 vence mañana, recuérdalo',
      'Gana \$5.000.000 con tu Tarjeta Nu',
      'Tu código de compra por \$45.900 es 482913',
      'Compra y devolución por \$45.000 en EXITO, abono de \$10.000',
      'Movimiento reportado por \$88.500 con TIENDA XYZ',
    ]) {
      test('does not guess from «$text»', () async {
        final outcome = await build().process(notice(text));
        expect(outcome, anyOf(NoticeOutcome.pending, NoticeOutcome.ignored));
        if (inbox.drafts.isNotEmpty) {
          expect(inbox.drafts.single.proposals, isEmpty);
        }
      });
    }
  });

  /// The user taps «Read with AI» on the item the processor saved last.
  Future<NoticeReadResult> readWithAi(_FakeAiClient ai) => build(
    ai: ai,
  ).readWithAi(itemOfDraft('item-${inbox.drafts.length}', inbox.drafts.last));

  group('the AI switch', () {
    // No template and no generic wording fits this text.
    const unknown = 'Movimiento reportado por \$88.500 con TIENDA XYZ';
    const answer =
        '{"is_transaction": true, "type": "expense", "amount": "88.500", "merchant": "TIENDA XYZ", "date": "03/11/2026"}';

    test('is off by default', () async {
      expect(await prefs.aiNoticesEnabled(), isFalse);
      expect(
        await NotificationsPrefs(MemoryKeyValueStore()).aiNoticesEnabled(),
        isFalse,
      );
    });

    test('off: nothing is sent and the notice waits for review', () async {
      final ai = _FakeAiClient(answer);
      final outcome = await build(ai: ai).process(notice(unknown));

      expect(outcome, NoticeOutcome.pending);
      expect(ai.calls, 0);
      expect(ai.sent, isEmpty);
      final draft = inbox.drafts.single;
      expect(draft.proposals, isEmpty);
      expect(draft.rawText, contains('TIENDA XYZ'));
      expect(draft.note, t.ia_notifications.pending_note);
      expect(draft.data, isNull);
    });

    test(
      'on: processing in the background makes no request and waits «to read with AI»',
      () async {
        await prefs.setAiNoticesEnabled(true);
        final ai = _FakeAiClient(answer);
        final outcome = await build(ai: ai).process(notice(unknown));

        expect(outcome, NoticeOutcome.pending);
        expect(ai.calls, 0);
        final draft = inbox.drafts.single;
        expect(draft.proposals, isEmpty);
        expect(draft.note, t.ia_notifications.pending_note_ai_manual);
        final sentence = draft.data?[InboxDataKeys.aiText] as String;
        expect(sentence, contains('TIENDA XYZ'));
        expect(sentence, contains('\$88.500'));
      },
    );

    test(
      'on: «Read with AI» makes one request with the sentence that was shown',
      () async {
        await prefs.setAiNoticesEnabled(true);
        final ai = _FakeAiClient(answer);
        await build(ai: ai).process(notice(unknown));
        final shown = inbox.drafts.single.data![InboxDataKeys.aiText];

        expect(await readWithAi(ai), NoticeReadResult.read);

        expect(ai.calls, 1);
        expect(ai.sent.last.text, shown);
        final finished = inbox.finished.single;
        expect(finished.proposal!.amount, 88500);
        expect(finished.note, isNull);
      },
    );

    test('on: the request asks the provider to stop at 512 tokens', () async {
      await prefs.setAiNoticesEnabled(true);
      final ai = _CappedAiClient(answer);
      await build(ai: ai).process(notice(unknown));
      await readWithAi(ai);

      expect(ai.requests, hasLength(1));
      expect(ai.requests.single, AiTokenCaps.notice);
      expect(AiTokenCaps.notice, 512);
    });

    test('on: the request has no balance, account or card number', () async {
      await prefs.setAiNoticesEnabled(true);
      final ai = _FakeAiClient('{"is_transaction": false}');
      await build(ai: ai).process(
        notice(
          'Movimiento reportado por \$88.500 con TIENDA XYZ el 03/11/2026 a las 20:35. '
          'Tu saldo disponible es \$15.430.200,00. Cuenta de ahorros 1234567890, '
          'tarjeta 4111 1111 1111 4321 terminada *4321. Titular Maria Fernanda Lopez, '
          'cupo \$2.000.000.',
        ),
      );
      expect(ai.calls, 0);
      await readWithAi(ai);

      expect(ai.calls, 1);
      final sent = ai.sent.map((m) => m.text).join('\n').toLowerCase();
      expect(sent, contains('tienda xyz'));
      expect(sent, contains('\$88.500'));
      expect(sent, contains('03/11/2026'));
      for (final leak in [
        'saldo',
        'disponible',
        'cupo',
        '15.430',
        '15430',
        '1234567890',
        '1234',
        '4111',
        '1111',
        '4321',
        '2.000.000',
      ]) {
        expect(sent, isNot(contains(leak)), reason: leak);
      }
    });

    test('on: a template match still spends no AI call', () async {
      await prefs.setAiNoticesEnabled(true);
      final ai = _FakeAiClient('{}');
      await build(ai: ai).process(notice('Pagaste \$45.900 en EXITO'));
      expect(ai.calls, 0);
      expect(inbox.drafts.single.data, isNull);
    });
  });

  group('unknown text', () {
    const unknown =
        'Movimiento reportado por \$88.500 con TIENDA XYZ el 03/11/2026';

    setUp(() => prefs.setAiNoticesEnabled(true));

    test('the AI reads it when the user asks', () async {
      final ai = _FakeAiClient(
        '{"is_transaction": true, "type": "expense", "amount": "88.500", "merchant": "TIENDA XYZ", "last4": "4321", "date": "03/11/2026"}',
      );
      await build(ai: ai, cards: {'4321': 'acc-9'}).process(notice(unknown));
      expect(ai.calls, 0);

      expect(await readWithAi(ai), NoticeReadResult.read);

      expect(ai.calls, 1);
      final row = inbox.finished.single.proposal!;
      expect(row.amount, 88500);
      expect(row.title, 'TIENDA XYZ');
      // The digits never reach the AI, so the account is not guessed from its answer.
      expect(row.accountId, isNull);
      expect(row.date, DateTime(2026, 11, 3, 9));
      expect(notifier.shown, hasLength(1));
    });

    test('an amount the AI invented in a bad format is not trusted', () async {
      final ai = _FakeAiClient(
        '{"is_transaction": true, "type": "expense", "amount": "mucho", "merchant": "X"}',
      );
      await build(ai: ai).process(notice(unknown));

      expect(await readWithAi(ai), NoticeReadResult.unclear);
      expect(inbox.finished.single.proposal, isNull);
    });

    test(
      'when the AI says it is not a movement the item says so and stays',
      () async {
        final ai = _FakeAiClient('{"is_transaction": false}');
        await build(ai: ai).process(notice(unknown));

        expect(await readWithAi(ai), NoticeReadResult.notMoney);

        expect(inbox.finished.single.proposal, isNull);
        expect(
          inbox.finished.single.note,
          t.ia_notifications.ai_not_money_note,
        );
      },
    );

    test('with the switch on and no AI set up the item waits', () async {
      final outcome = await build().process(notice(unknown));

      expect(outcome, NoticeOutcome.pending);
      final draft = inbox.drafts.single;
      expect(draft.proposals, isEmpty);
      expect(draft.rawText, contains('TIENDA XYZ'));
      expect(draft.note, isNotNull);
      expect(notifier.shown.single.body, 'New movement to review');
    });

    for (final answer in [
      '{}',
      '{"is_transaction":"true"}',
      '{"is_transaction": 1}',
      '{"is_transaction": true}',
      '{"is_transaction": true, "type": "gasto", "amount": "88.500"}',
      '{"is_transaction": true, "type": "income"}',
    ]) {
      test(
        'an AI answer without a clear decision keeps the text: $answer',
        () async {
          final ai = _FakeAiClient(answer);
          await build(ai: ai).process(notice(unknown));

          expect(await readWithAi(ai), NoticeReadResult.unclear);

          expect(inbox.drafts.single.rawText, contains('TIENDA XYZ'));
          final finished = inbox.finished.single;
          expect(finished.proposal, isNull);
          expect(finished.note, t.ia_notifications.pending_note_ai);
        },
      );
    }

    test('only an explicit income type is an income', () async {
      final ai = _FakeAiClient(
        '{"is_transaction": true, "type": "income", "amount": "88.500", "merchant": "ABONO"}',
      );
      await build(ai: ai).process(notice(unknown));
      await readWithAi(ai);
      expect(inbox.finished.single.proposal!.type, TransactionType.income);
    });

    test('the AI sees the text with codes and numbers masked', () async {
      final ai = _FakeAiClient('{"is_transaction": false}');
      await build(ai: ai).process(
        notice(
          'Movimiento en tu cuenta 123456789: débito por \$88.500 en TIENDA XYZ. Clave de un solo uso 482913',
        ),
      );
      await readWithAi(ai);
      final sent = ai.sent.last.text;
      expect(sent, contains('TIENDA XYZ'));
      expect(sent, contains('\$88.500'));
      expect(sent, isNot(contains('123456789')));
      expect(sent, isNot(contains('482913')));
    });

    test('the saved text has codes and account numbers masked', () async {
      await build().process(
        notice(
          'Movimiento en tu cuenta 123456789: débito por \$88.500 en TIENDA XYZ. Clave de un solo uso 482913',
        ),
      );
      final text = inbox.drafts.single.rawText;
      expect(text, contains('TIENDA XYZ'));
      expect(text, contains('\$88.500'));
      expect(text, isNot(contains('123456789')));
      expect(text, isNot(contains('482913')));
    });

    test('when the AI fails the item is left as it was', () async {
      final ai = _FakeAiClient('', fail: true);
      await build(ai: ai).process(notice(unknown));

      expect(await readWithAi(ai), NoticeReadResult.failed);

      expect(inbox.finished, isEmpty);
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
