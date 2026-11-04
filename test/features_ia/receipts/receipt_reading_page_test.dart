import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';
import 'package:monekin/features_ia/receipts/receipt_reading_page.dart';
import 'package:monekin/features_ia/receipts/receipt_store.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class _EmptyCatalog extends AiCatalog {
  const _EmptyCatalog() : super(accounts: const [], categories: const []);

  @override
  String toPromptJson() => '{}';
}

class _OfflineClient implements AiClient {
  int calls = 0;

  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls++;
    throw const AiException(AiErrorKind.network, 'offline');
  }

  @override
  Future<List<String>> listModels() async => [];
}

/// Fails the first save, then stores drafts normally.
class _FlakyInbox extends NotReadyInboxService {
  final drafts = <InboxDraft>[];
  bool _failNext = true;

  @override
  Future<String> addItem(InboxDraft draft) async {
    drafts.add(draft);
    if (_failNext) {
      _failNext = false;
      throw StateError('disk full');
    }
    return 'item-${drafts.length}';
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory tmp;
  late InboxService previousInbox;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('receipt_reading_test');
    previousInbox = InboxService.instance;
  });

  tearDown(() {
    InboxService.instance = previousInbox;
    tmp.deleteSync(recursive: true);
  });

  testWidgets('a failed save keeps the photo and retry saves the same draft', (
    tester,
  ) async {
    final file = File('${tmp.path}/abc.jpg')..writeAsBytesSync([1, 2, 3]);
    final photo = SavedReceiptPhoto(
      path: file.path,
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    final client = _OfflineClient();
    final inbox = _FlakyInbox();
    InboxService.instance = inbox;
    final analyzer = ReceiptAnalyzer(
      clientProvider: () async => client,
      catalogLoader: () async => const _EmptyCatalog(),
      cardMapLoader: () async => {},
      accountForLast4: (_) async => null,
      parseAmount: (_) => null,
    );
    List<String>? ids;

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                ids = await Navigator.of(context).push<List<String>>(
                  MaterialPageRoute(
                    builder: (_) =>
                        ReceiptReadingPage(photos: [photo], analyzer: analyzer),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);

    expect(find.byType(FilledButton), findsOneWidget);
    expect(file.existsSync(), isTrue);
    expect(inbox.drafts, hasLength(1));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(client.calls, 1);
    expect(inbox.drafts, hasLength(2));
    expect(identical(inbox.drafts[0], inbox.drafts[1]), isTrue);
    expect(inbox.drafts[1].attachmentPaths, [file.path]);
    expect(inbox.drafts[1].proposals, isEmpty);
    expect(inbox.drafts[1].note, isNotNull);
    expect(ids, ['item-2']);
    expect(find.byType(ReceiptReadingPage), findsNothing);
  });
}
