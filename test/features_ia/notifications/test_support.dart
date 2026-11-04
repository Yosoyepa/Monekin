import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';

/// `parseLocalizedAmount`. While the skeleton version (throws UnimplementedError) is still in this branch,
/// a small Colombian parser with the same rules stands in; once w-utils lands the real one answers.
double? testAmountParser(String raw) {
  try {
    return parseLocalizedAmount(raw);
  } on UnimplementedError {
    var s = raw.replaceAll(RegExp(r'[^\d.,]'), '');
    if (s.isEmpty) return null;
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      final decimalSep = lastDot > lastComma ? '.' : ',';
      final thousandSep = decimalSep == '.' ? ',' : '.';
      s = s.replaceAll(thousandSep, '').replaceAll(decimalSep, '.');
    } else if (lastDot >= 0 || lastComma >= 0) {
      final sep = lastDot >= 0 ? '.' : ',';
      final parts = s.split(sep);
      final thousands = parts.length > 2 || parts.last.length == 3;
      s = thousands ? parts.join() : '${parts[0]}.${parts[1]}';
    }
    return double.tryParse(s);
  }
}

class FakeInbox implements InboxService {
  final List<InboxDraft> drafts = [];
  bool failNext = false;

  @override
  Future<String> addItem(InboxDraft draft) async {
    if (failNext) {
      failNext = false;
      throw StateError('inbox down');
    }
    drafts.add(draft);
    return 'item-${drafts.length}';
  }

  @override
  Stream<List<InboxItem>> watchItems({InboxStatus? status}) =>
      const Stream.empty();

  @override
  Stream<int> watchPendingCount() => Stream.value(0);

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

class ShownNotification {
  ShownNotification(this.id, this.channel, this.title, this.body, this.payload);

  final int id;
  final AlertChannel channel;
  final String title;
  final String body;
  final String? payload;
}

class FakeNotifier implements LocalNotifier {
  final List<ShownNotification> shown = [];

  @override
  Future<void> show({
    required int id,
    required AlertChannel channel,
    required String title,
    required String body,
    String? payload,
  }) async {
    shown.add(ShownNotification(id, channel, title, body, payload));
  }
}
