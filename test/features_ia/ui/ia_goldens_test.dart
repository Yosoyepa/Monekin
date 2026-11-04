// Goldens of the AI screens at 360 dp, in light and dark. They are drawn with
// reduced motion, so Chanchi and the lists show their final frame.
//
// Generated on Windows: text may differ by a pixel on another OS.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/core/dedupe/dedupe.dart' as dedupe;
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_page.dart';
import 'package:monekin/features_ia/inbox/inbox_review_page.dart';
import 'package:monekin/features_ia/notifications/bank_apps.dart';
import 'package:monekin/features_ia/settings/ai_settings_page.dart';
import 'package:monekin/features_ia/statements/reconciliation_card.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../../brand/brand_test_utils.dart';
import '../inbox/inbox_review_page_test.dart'
    show FakeInboxService, FakeLookup, fakeParse;

const _width = 360.0;

Widget _app(Widget home, {required bool dark}) => TranslationProvider(
  child: brandApp(home, dark: dark, disableAnimations: true),
);

/// Loads the Material icon font of the SDK, so goldens draw icons, not boxes.
Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// Lets the SVG layers and the photo files load (they use real I/O).
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(ChanchiMascot.preload);
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

Future<void> _surface(WidgetTester tester, double height) async {
  await tester.binding.setSurfaceSize(Size(_width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// A small receipt-like picture, so the thumbnail shows a photo.
Future<String> _photo(WidgetTester tester, Directory dir) async {
  final path = '${dir.path}/receipt.png';

  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paper = Paint()..color = const Color(0xFFF4EBDD);
    final ink = Paint()..color = const Color(0xFF5B4B3F);

    canvas.drawRect(const Rect.fromLTWH(0, 0, 240, 240), paper);
    for (var i = 0; i < 9; i++) {
      canvas.drawRect(
        Rect.fromLTWH(32, 40 + i * 20.0, i.isEven ? 176 : 120, 6),
        ink,
      );
    }
    final image = await recorder.endRecording().toImage(240, 240);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  return path;
}

ProposedTransaction _row(
  String title,
  double amount, {
  TransactionType type = TransactionType.expense,
}) => ProposedTransaction(
  date: DateTime(2026, 10, 20, 13, 30),
  title: title,
  amount: amount,
  type: type,
  categoryId: 'cat-e',
  accountId: 'acc-1',
);

/// Serves a fixed list for the pending tab.
class _ListService extends FakeInboxService {
  _ListService(this.items) : super(items.first);

  final List<InboxItem> items;

  @override
  Stream<int> watchPendingCount() =>
      Stream.value(items.where((i) => i.status == InboxStatus.pending).length);

  @override
  Stream<List<InboxItem>> watchItems({InboxStatus? status}) => Stream.value([
    for (final item in items)
      if (status == null || status == item.status) item,
  ]);
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    await loadBrandFonts();
    await _loadIcons();
  });
  setUp(() => tmp = Directory.systemTemp.createTempSync('ia_goldens'));
  // Windows keeps the decoded photo open for a moment: a stray temp file is fine.
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Left for the system to clean up.
    }
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';

    testWidgets('inbox empty $name', (tester) async {
      await _surface(tester, 640);
      final service = _ListService([
        InboxItem(
          id: 'x',
          source: InboxSource.receipt,
          sourceRef: 'x',
          status: InboxStatus.processed,
          createdAt: DateTime(2026),
          proposals: const [],
        ),
      ]);

      await tester.pumpWidget(
        _app(
          InboxPage(service: service, lookup: FakeLookup()),
          dark: dark,
        ),
      );
      await _settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/inbox_empty_$name.png'),
      );
    });

    testWidgets('inbox with three items $name', (tester) async {
      await _surface(tester, 460);
      final photo = await _photo(tester, tmp);
      final service = _ListService([
        InboxItem(
          id: 'receipt',
          source: InboxSource.receipt,
          sourceRef: 'f3a2b7c1-9d4e-4c1a-8b55-0a1e2d3c4b5a.jpg',
          status: InboxStatus.pending,
          createdAt: DateTime(2026, 10, 20, 13, 30),
          attachmentPaths: [photo],
          proposals: [_row('KFC Unicentro', 45900)],
        ),
        InboxItem(
          id: 'statement',
          source: InboxSource.statement,
          sourceRef: 'nequi-2026-10',
          status: InboxStatus.pending,
          createdAt: DateTime(2026, 10, 18),
          proposals: [
            _row('Pago en tienda', 14500),
            _row('Recarga celular', 20000),
            _row('Recepcion de Maria', 80000, type: TransactionType.income),
          ],
        ),
        InboxItem(
          id: 'notice',
          source: InboxSource.notification,
          sourceRef: kKnownBankApps.first.package,
          status: InboxStatus.pending,
          createdAt: DateTime(2026, 10, 17),
          proposals: [_row('Compra con tarjeta', 128000)],
        ),
      ]);

      await tester.pumpWidget(
        _app(
          InboxPage(service: service, lookup: FakeLookup()),
          dark: dark,
        ),
      );
      await _settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/inbox_three_$name.png'),
      );
    });

    testWidgets('receipt review with photo and duplicate $name', (
      tester,
    ) async {
      await _surface(tester, 1180);
      final photo = await _photo(tester, tmp);
      final item = InboxItem(
        id: 'item-1',
        source: InboxSource.receipt,
        sourceRef: 'f3a2b7c1-9d4e-4c1a-8b55-0a1e2d3c4b5a.jpg',
        status: InboxStatus.pending,
        createdAt: DateTime(2026, 10, 20, 13, 30),
        attachmentPaths: [photo],
        proposals: [_row('KFC Unicentro', 45900)],
      );
      final service = FakeInboxService(item)
        ..previewed = const [
          DuplicateWarning(
            rowIndex: 0,
            existingTransactionId: 'tx-old',
            reason: dedupe.duplicateOfExisting,
          ),
        ];

      await tester.pumpWidget(
        _app(
          InboxReviewPage(
            itemId: 'item-1',
            service: service,
            lookup: FakeLookup(),
            parseAmount: fakeParse,
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      await _settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/review_receipt_$name.png'),
      );
    });

    testWidgets('AI settings $name', (tester) async {
      await _surface(tester, 1180);
      final directory = Directory.systemTemp.createTempSync('ia_settings');
      addTearDown(() {
        try {
          directory.deleteSync(recursive: true);
        } on FileSystemException {
          // Left for the system to clean up.
        }
      });
      FlutterSecureStorage.setMockInitialValues({});
      final service = AiServiceImpl(
        configFile: () async => File('${directory.path}/settings.json'),
      );
      final previous = AiService.instance;
      AiService.instance = service;
      addTearDown(() => AiService.instance = previous);

      await tester.runAsync(() async {
        await service.saveConfig(aiPresets[AiProviderId.gemini]!);
        await service.saveKey('golden-key', aiPresets[AiProviderId.gemini]!);
        await tester.pumpWidget(_app(const AiSettingsPage(), dark: dark));
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          if (find.byKey(const ValueKey('ai-key')).evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ai_settings_$name.png'),
      );
    });

    testWidgets('statement reconciliation card $name', (tester) async {
      await _surface(tester, 600);
      final money = iaMoneyFormat(symbol: r'$', decimals: 2);

      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  ReconciliationCard(
                    reconciliation: (net: 45500.0, difference: 0.0),
                    format: money,
                    margin: const EdgeInsets.only(bottom: 16),
                  ),
                  ReconciliationCard(
                    reconciliation: (net: -62300.5, difference: 1200.0),
                    format: money,
                  ),
                ],
              ),
            ),
          ),
          dark: dark,
        ),
      );
      await _settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reconciliation_$name.png'),
      );
    });
  }
}
