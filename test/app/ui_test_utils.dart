import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../brand/brand_test_utils.dart';

export '../brand/brand_test_utils.dart';

/// Brand app with translations, like `main.dart` builds it.
Widget uiApp(Widget home, {bool dark = false, bool disableAnimations = false}) {
  return TranslationProvider(
    child: brandApp(home, dark: dark, disableAnimations: disableAnimations),
  );
}

/// Loads the Nunito fonts and the Material icon font, so goldens show real
/// text and icons instead of boxes.
Future<void> loadUiFonts() async {
  await loadBrandFonts();

  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;

  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!icons.existsSync()) return;

  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await loader.load();
}

/// Sets the phone-sized surface of the test in logical pixels; [ratio] only
/// sharpens the goldens.
Future<void> useSurface(
  WidgetTester tester,
  double width,
  double height, {
  double ratio = 1,
}) async {
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = Size(width * ratio, height * ratio);
  addTearDown(tester.view.reset);
}

/// An inbox whose pending count the test drives.
class FakeInbox implements InboxService {
  FakeInbox(this.pending);

  final Stream<int> pending;

  @override
  Stream<int> watchPendingCount() => pending;

  @override
  Future<String> addItem(InboxDraft draft) => throw UnimplementedError();

  @override
  Stream<List<InboxItem>> watchItems({InboxStatus? status}) =>
      const Stream.empty();

  @override
  Future<InboxItem?> getItem(String id) async => null;

  @override
  Future<ConfirmResult> confirm(
    String itemId,
    List<ProposedTransaction> rows,
  ) => throw UnimplementedError();

  @override
  Future<void> discard(String itemId, {String? reason}) =>
      throw UnimplementedError();
}
