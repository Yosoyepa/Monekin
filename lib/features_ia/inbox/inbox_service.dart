// Contract of the AI inbox service (T002). Owner: w-inbox.
import 'package:monekin/features_ia/inbox/inbox_models.dart';

abstract class InboxService {
  /// Replaced at startup by `initFeaturesIa()` with the drift implementation.
  static InboxService instance = NotReadyInboxService();

  /// Stores a new pending item and returns its id.
  Future<String> addItem(InboxDraft draft);

  Stream<List<InboxItem>> watchItems({InboxStatus? status});

  Stream<int> watchPendingCount();

  Future<InboxItem?> getItem(String id);

  /// Validates and deduplicates [rows], creates the transactions that pass
  /// (tag `ia`, notes ending in `[origen: ...]`, attachments linked to the first
  /// one) and marks the item processed when no row failed.
  Future<ConfirmResult> confirm(String itemId, List<ProposedTransaction> rows);

  Future<void> discard(String itemId, {String? reason});
}

/// Implemented by the stored inbox. Finishes a notice that waited for the user to read it with the AI: it keeps the
/// [proposal] the AI read (none when it could not) and stops asking, with [note] as the text of the item.
abstract interface class InboxNoticeReading {
  Future<void> finishAiNotice(
    String itemId, {
    ProposedTransaction? proposal,
    String? note,
  });
}

/// Placeholder used before startup and in tests that do not need the inbox.
class NotReadyInboxService implements InboxService {
  @override
  Future<String> addItem(InboxDraft draft) =>
      throw UnimplementedError('InboxService not ready');

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
  ) => throw UnimplementedError('InboxService not ready');

  @override
  Future<void> discard(String itemId, {String? reason}) =>
      throw UnimplementedError('InboxService not ready');
}
