// Consent of the AI functions (T002, round 3): nothing is sent until the user accepts, per function and per destination.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/core/consent/ai_consent_sheet.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_service_impl.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../notifications/test_support.dart';
import '../utils/consent_support.dart';

const _gemini = AiProviderConfig(
  provider: AiProviderId.gemini,
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  model: 'gemini-flash-lite-latest',
);
const _deepseek = AiProviderConfig(
  provider: AiProviderId.deepseek,
  baseUrl: 'https://api.deepseek.com',
  model: 'deepseek-flash',
);

class _Catalog extends AiCatalog {
  const _Catalog()
    : super(
        accounts: const [
          CatalogAccount(id: 'acc-1', name: 'Cuenta', currency: 'COP'),
        ],
        categories: const [
          CatalogCategory(id: 'cat-food', name: 'Food', type: 'E'),
        ],
      );
}

void main() {
  tearDown(() => AiService.debugClientOverride = null);

  group('the stored answers', () {
    late Directory dir;
    late AiConsent consent;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ai_consent_store');
      consent = AiConsent(file: () async => File('${dir.path}/consent.json'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('start empty: nothing is allowed', () async {
      for (final feature in AiFeature.values) {
        expect(await consent.isGranted(feature, _gemini), isFalse);
      }
    });

    test('are kept per function and survive a new instance', () async {
      await consent.grant(AiFeature.receipt, _gemini);

      final again = AiConsent(
        file: () async => File('${dir.path}/consent.json'),
      );
      expect(await again.isGranted(AiFeature.receipt, _gemini), isTrue);
      expect(await again.isGranted(AiFeature.statement, _gemini), isFalse);
    });

    test('revoking one function leaves the others', () async {
      await consent.grant(AiFeature.receipt, _gemini);
      await consent.grant(AiFeature.statement, _gemini);

      await consent.revoke(AiFeature.receipt, _gemini);

      expect(await consent.isGranted(AiFeature.receipt, _gemini), isFalse);
      expect(await consent.isGranted(AiFeature.statement, _gemini), isTrue);
    });

    test('a change of provider asks again in every function', () async {
      for (final feature in AiFeature.values) {
        await consent.grant(feature, _gemini);
      }

      for (final feature in AiFeature.values) {
        expect(await consent.isGranted(feature, _deepseek), isFalse);
      }
      await consent.grant(AiFeature.notice, _deepseek);
      expect(await consent.isGranted(AiFeature.notice, _deepseek), isTrue);
      expect(await consent.isGranted(AiFeature.receipt, _gemini), isFalse);
    });

    test('a change of host asks again in every function', () async {
      const mine = AiProviderConfig(
        provider: AiProviderId.custom,
        baseUrl: 'https://uno.example/v1',
        model: 'm',
      );
      const other = AiProviderConfig(
        provider: AiProviderId.custom,
        baseUrl: 'https://dos.example/v1',
        model: 'm',
      );
      for (final feature in AiFeature.values) {
        await consent.grant(feature, mine);
      }

      for (final feature in AiFeature.values) {
        expect(await consent.isGranted(feature, other), isFalse);
      }
    });

    test('a damaged file counts as no consent', () async {
      File('${dir.path}/consent.json').writeAsStringSync('{not json');

      expect(await consent.isGranted(AiFeature.receipt, _gemini), isFalse);
    });
  });

  group('without consent no function sends anything', () {
    late RecordingAiClient client;

    setUp(() async {
      await useTestConsent(grantAll: false);
      client = RecordingAiClient('{}');
      AiService.debugClientOverride = client;
    });

    test('aiClientFor refuses until the function is accepted', () async {
      await expectLater(
        aiClientFor(AiFeature.insights),
        throwsA(isA<AiException>()),
      );

      await AiConsent.instance.grant(
        AiFeature.insights,
        await currentAiConfig(),
      );

      expect(await aiClientFor(AiFeature.insights), same(client));
      await expectLater(
        aiClientFor(AiFeature.receipt),
        throwsA(isA<AiException>()),
      );
    });

    test('receipts: 0 requests, then 1 once accepted', () async {
      client.answer =
          '{"date":"2026-11-03","merchant":"EXITO","total":45900,"category_id":null,"card_last4":null,"warning":null}';
      final analyzer = ReceiptAnalyzer(
        catalogLoader: () async => const _Catalog(),
        accountForLast4: (_) async => null,
        parseAmount: testAmountParser,
      );
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

      final denied = await analyzer.analyze(
        imageBytes: jpeg,
        filePath: 'a.jpg',
        fileName: 'a.jpg',
      );
      expect(client.requests, isEmpty);
      expect(denied.proposals, isEmpty);

      await AiConsent.instance.grant(
        AiFeature.receipt,
        await currentAiConfig(),
      );
      final allowed = await analyzer.analyze(
        imageBytes: jpeg,
        filePath: 'a.jpg',
        fileName: 'a.jpg',
      );
      expect(client.requests, hasLength(1));
      expect(allowed.proposals.single.amount, 45900);
    });

    test('statements: reading and categories send nothing', () async {
      final importer = StatementImporter(
        catalogLoader: () async => const _Catalog(),
      );

      await expectLater(
        importer.parseWithAi('01/11/2026 EXITO -45.900', 'acc-1'),
        throwsA(isA<AiException>()),
      );
      final result = await importer.proposeCategories(
        StatementResult(
          [
            ProposedTransaction(
              date: DateTime(2026, 11, 1),
              title: 'EXITO',
              amount: 45900,
            ),
          ],
          null,
          null,
        ),
      );

      expect(client.requests, isEmpty);
      expect(result.categoryWarning, isTrue);
    });

    test('notices: «Read with AI» sends nothing', () async {
      final inbox = FakeInbox();
      final processor = NotificationProcessor(
        prefs: NotificationsPrefs(MemoryKeyValueStore()),
        notifier: FakeNotifier(),
        inbox: () => inbox,
        accountForCard: (_) async => null,
        parseAmount: testAmountParser,
      );
      final item = itemOfDraft(
        'item-1',
        InboxDraft(
          source: InboxSource.notification,
          sourceRef: 'com.nequi.MobileApp',
          proposals: const [],
          data: {InboxDataKeys.aiText: 'Movimiento por \$88.500 con TIENDA'},
        ),
      );

      expect(await processor.readWithAi(item), NoticeReadResult.failed);
      expect(client.requests, isEmpty);
    });

    test('insights: the weekly summary keeps the local tip', () async {
      final service = InsightsServiceImpl(
        loadExpenses: (start, end) async => [
          InsightTransaction(
            title: 'Almuerzo',
            amount: 50000,
            date: DateTime(2026, 11, 3),
            categoryId: 'food',
            categoryName: 'Comida',
          ),
        ],
        preferredCurrency: () async => const CurrencyInDB(
          code: 'COP',
          symbol: r'$',
          name: 'Peso',
          decimalPlaces: 0,
          isDefault: true,
          type: 0,
        ),
        languageName: () => 'Spanish',
        now: () => DateTime(2026, 11, 4),
      );

      final summary = await service.weeklySummary();

      expect(summary, isNotNull);
      expect(client.requests, isEmpty);
    });
  });

  group('the sheet', () {
    Widget app(Future<bool> Function(BuildContext) ask, List<bool> answers) =>
        TranslationProvider(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('ask'),
                    onPressed: () async => answers.add(await ask(context)),
                    child: const Text('ask'),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('asks the first time and says what, to whom and what never', (
      tester,
    ) async {
      final consent = await useTestConsent(grantAll: false);
      final answers = <bool>[];
      await tester.pumpWidget(
        app((c) => ensureAiConsent(c, AiFeature.receipt), answers),
      );

      await tester.tap(find.byKey(const Key('ask')));
      await tester.pumpAndSettle();

      final t = Translations.of(tester.element(find.byType(AiConsentSheet)));
      expect(find.text(t.ia_consent.sent_receipt), findsOneWidget);
      expect(
        find.textContaining('generativelanguage.googleapis.com'),
        findsOneWidget,
      );
      expect(find.text(t.ia_consent.never_sent_body), findsOneWidget);
      expect(find.text(t.ia_consent.accept), findsOneWidget);
      expect(find.text(t.ia_consent.decline), findsOneWidget);

      await tester.tap(find.byKey(const Key('consent-accept')));
      await tester.pumpAndSettle();

      expect(answers, [true]);
      expect(await consent.isGranted(AiFeature.receipt, _gemini), isTrue);
    });

    testWidgets('«No usar IA aquí» answers no and keeps nothing', (
      tester,
    ) async {
      final consent = await useTestConsent(grantAll: false);
      final answers = <bool>[];
      await tester.pumpWidget(
        app((c) => ensureAiConsent(c, AiFeature.statement), answers),
      );

      await tester.tap(find.byKey(const Key('ask')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consent-decline')));
      await tester.pumpAndSettle();

      expect(answers, [false]);
      expect(await consent.isGranted(AiFeature.statement, _gemini), isFalse);
    });

    testWidgets(
      'does not ask again once accepted, and asks again after revoking',
      (tester) async {
        final consent = await useTestConsent(grantAll: false);
        await consent.grant(AiFeature.insights, _gemini);
        final answers = <bool>[];
        await tester.pumpWidget(
          app((c) => ensureAiConsent(c, AiFeature.insights), answers),
        );

        await tester.tap(find.byKey(const Key('ask')));
        await tester.pumpAndSettle();
        expect(find.byType(AiConsentSheet), findsNothing);
        expect(answers, [true]);

        await consent.revoke(AiFeature.insights, _gemini);
        await tester.tap(find.byKey(const Key('ask')));
        await tester.pumpAndSettle();
        expect(find.byType(AiConsentSheet), findsOneWidget);
      },
    );
  });
}
