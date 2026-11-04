import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';
import 'package:monekin/features_ia/receipts/receipt_store.dart';

class _EmptyCatalog extends AiCatalog {
  const _EmptyCatalog() : super(accounts: const [], categories: const []);

  @override
  String toPromptJson() => '{}';
}

class _FailingClient implements AiClient {
  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async => throw const AiException(AiErrorKind.network, 'offline');

  @override
  Future<List<String>> listModels() async => [];
}

class _RecordingInbox extends NotReadyInboxService {
  final drafts = <InboxDraft>[];

  @override
  Future<String> addItem(InboxDraft draft) async {
    drafts.add(draft);
    return 'item-${drafts.length}';
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('receipt_store_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'saveReceiptPhoto copies the photo to finanzas_ia/receipts/<uuid>.jpg',
    () async {
      final source = File('${tmp.path}/shot.jpg')
        ..writeAsBytesSync([1, 2, 3, 4]);

      final saved = await saveReceiptPhoto(source, baseDir: tmp);

      expect(
        saved.path,
        startsWith(
          '${tmp.path}${Platform.pathSeparator}finanzas_ia${Platform.pathSeparator}receipts',
        ),
      );
      expect(RegExp(r'^[0-9a-f-]{36}\.jpg$').hasMatch(saved.fileName), isTrue);
      expect(File(saved.path).readAsBytesSync(), [1, 2, 3, 4]);
      expect(saved.bytes, [1, 2, 3, 4]);
    },
  );

  test(
    'when the AI fails the receipt still reaches the inbox, without a proposal and with the notice',
    () async {
      final inbox = _RecordingInbox();
      final analyzer = ReceiptAnalyzer(
        clientProvider: () async => _FailingClient(),
        catalogLoader: () async => const _EmptyCatalog(),
        cardMapLoader: () async => {},
        accountForLast4: (_) async => null,
        parseAmount: (_) => null,
      );
      final photo = SavedReceiptPhoto(
        path: '${tmp.path}/abc.jpg',
        bytes: Uint8List.fromList([1]),
      );

      final id = await addReceiptToInbox(
        photo,
        analyzer: analyzer,
        inbox: inbox,
      );

      expect(id, 'item-1');
      final draft = inbox.drafts.single;
      expect(draft.source, InboxSource.receipt);
      expect(draft.proposals, isEmpty);
      expect(draft.note, ReceiptMessages.defaultAiError(AiErrorKind.network));
      expect(draft.attachmentPaths, [photo.path]);
      expect(draft.sourceRef, 'abc.jpg');
    },
  );
}
