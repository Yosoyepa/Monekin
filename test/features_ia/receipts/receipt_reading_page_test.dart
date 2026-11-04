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

ReceiptAnalyzer _offlineAnalyzer(AiClient client) => ReceiptAnalyzer(
  clientProvider: () async => client,
  catalogLoader: () async => const _EmptyCatalog(),
  accountForLast4: (_) async => null,
  parseAmount: (_) => null,
);

SavedReceiptPhoto _photo(Directory dir, String name) {
  final file = File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);
  return SavedReceiptPhoto(
    path: file.path,
    bytes: Uint8List.fromList([1, 2, 3]),
  );
}

/// Opens the reading page from a host route and reports the ids it pops with.
Future<void> _openReading(
  WidgetTester tester, {
  required List<SavedReceiptPhoto> photos,
  required ReceiptAnalyzer analyzer,
  required void Function(List<String>? ids) onResult,
}) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final ids = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(
                  builder: (_) =>
                      ReceiptReadingPage(photos: photos, analyzer: analyzer),
                ),
              );
              onResult(ids);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Finds widgets inside the reading page only, not the host route behind it.
Finder _inPage(Finder finder) =>
    find.descendant(of: find.byType(ReceiptReadingPage), matching: finder);

/// Taps the discard button, then the dialog's confirm or cancel button.
Future<void> _tapDiscard(WidgetTester tester, {required bool confirm}) async {
  await tester.tap(_inPage(find.byType(TextButton)));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(confirm ? FilledButton : TextButton),
    ),
  );
  await tester.pumpAndSettle();
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
    final photo = _photo(tmp, 'abc.jpg');
    final client = _OfflineClient();
    final inbox = _FlakyInbox();
    InboxService.instance = inbox;
    List<String>? ids;

    await _openReading(
      tester,
      photos: [photo],
      analyzer: _offlineAnalyzer(client),
      onResult: (value) => ids = value,
    );

    expect(_inPage(find.byType(FilledButton)), findsOneWidget);
    expect(File(photo.path).existsSync(), isTrue);
    expect(inbox.drafts, hasLength(1));

    await tester.tap(_inPage(find.byType(FilledButton)));
    await tester.pumpAndSettle();

    expect(client.calls, 1);
    expect(inbox.drafts, hasLength(2));
    expect(identical(inbox.drafts[0], inbox.drafts[1]), isTrue);
    expect(inbox.drafts[1].attachmentPaths, [photo.path]);
    expect(inbox.drafts[1].proposals, isEmpty);
    expect(inbox.drafts[1].note, isNotNull);
    expect(ids, ['item-2']);
    expect(find.byType(ReceiptReadingPage), findsNothing);
  });

  testWidgets(
    'discarding a failed receipt deletes its photo and closes the screen',
    (tester) async {
      final photo = _photo(tmp, 'abc.jpg');
      final client = _OfflineClient();
      final inbox = _FlakyInbox();
      InboxService.instance = inbox;
      List<String>? ids;

      await _openReading(
        tester,
        photos: [photo],
        analyzer: _offlineAnalyzer(client),
        onResult: (value) => ids = value,
      );
      await _tapDiscard(tester, confirm: true);

      expect(File(photo.path).existsSync(), isFalse);
      expect(client.calls, 1);
      expect(inbox.drafts, hasLength(1));
      expect(ids, isEmpty);
      expect(find.byType(ReceiptReadingPage), findsNothing);
    },
  );

  testWidgets('cancelling the discard keeps the photo and the retry button', (
    tester,
  ) async {
    final photo = _photo(tmp, 'abc.jpg');
    final client = _OfflineClient();
    final inbox = _FlakyInbox();
    InboxService.instance = inbox;
    List<String>? ids;

    await _openReading(
      tester,
      photos: [photo],
      analyzer: _offlineAnalyzer(client),
      onResult: (value) => ids = value,
    );
    await _tapDiscard(tester, confirm: false);

    expect(File(photo.path).existsSync(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_inPage(find.byType(FilledButton)), findsOneWidget);
    expect(inbox.drafts, hasLength(1));
    expect(ids, isNull);
  });

  testWidgets('discarding one photo of a batch keeps reading the next one', (
    tester,
  ) async {
    final first = _photo(tmp, 'first.jpg');
    final second = _photo(tmp, 'second.jpg');
    final client = _OfflineClient();
    final inbox = _FlakyInbox();
    InboxService.instance = inbox;
    List<String>? ids;

    await _openReading(
      tester,
      photos: [first, second],
      analyzer: _offlineAnalyzer(client),
      onResult: (value) => ids = value,
    );
    await _tapDiscard(tester, confirm: true);

    expect(File(first.path).existsSync(), isFalse);
    expect(File(second.path).existsSync(), isTrue);
    expect(client.calls, 2);
    expect(inbox.drafts, hasLength(2));
    expect(inbox.drafts[1].attachmentPaths, [second.path]);
    expect(ids, ['item-2']);
  });
}
