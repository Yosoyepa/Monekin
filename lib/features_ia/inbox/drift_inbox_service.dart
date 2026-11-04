// Drift implementation of the AI inbox (T002). Owner: w-inbox.
// The only code that writes transactions coming from the AI: `confirm`.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_status.enum.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/utils/uuid.dart';
import 'package:monekin/features_ia/core/dedupe/dedupe.dart' as dedupe;
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

typedef DuplicateFinder =
    List<dedupe.DedupeMatch> Function(
      List<dedupe.DedupeCandidate> rows,
      List<dedupe.DedupeCandidate> existing,
    );

/// Name of the tag put on every transaction created from the inbox.
const inboxTagName = 'ia';

/// Color (hex without `#`) of the `ia` tag when it has to be created.
const _inboxTagColor = '4385be';

/// Optional capability of an [InboxService]: finds the duplicates of the rows
/// before the user confirms them, so the review page can warn about them.
abstract interface class InboxDuplicatePreview {
  Future<List<DuplicateWarning>> previewDuplicates(
    List<ProposedTransaction> rows,
  );
}

class DriftInboxService implements InboxService, InboxDuplicatePreview {
  DriftInboxService({
    required this.db,
    required this.transactions,
    this.findDuplicates = dedupe.findDuplicates,
  });

  final AppDB db;
  final TransactionService transactions;

  /// Injected so the service can be tested before `findDuplicates` exists.
  final DuplicateFinder findDuplicates;

  @override
  Future<String> addItem(InboxDraft draft) async {
    final id = generateUUID();

    await db
        .into(db.aiInboxItems)
        .insert(
          AiInboxItemsCompanion.insert(
            id: id,
            source: draft.source.name,
            sourceRef: draft.sourceRef,
            createdAt: DateTime.now(),
            proposalsJson: _encodeProposals(draft.proposals),
            rawText: Value(draft.rawText),
            attachmentsJson: Value(jsonEncode(draft.attachmentPaths)),
            resultTransactionIdsJson: Value(jsonEncode(<String>[])),
            note: Value(draft.note),
          ),
        );

    return id;
  }

  @override
  Stream<List<InboxItem>> watchItems({InboxStatus? status}) {
    final query = db.select(db.aiInboxItems)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

    if (status != null) {
      query.where((t) => t.status.equals(status.name));
    }

    return query.watch().map((rows) => rows.map(_toItem).toList());
  }

  @override
  Stream<int> watchPendingCount() {
    final count = db.aiInboxItems.id.count();

    return (db.selectOnly(db.aiInboxItems)
          ..addColumns([count])
          ..where(db.aiInboxItems.status.equals(InboxStatus.pending.name)))
        .watchSingle()
        .map((row) => row.read(count) ?? 0);
  }

  @override
  Future<InboxItem?> getItem(String id) async {
    final row = await _getRow(id);
    return row == null ? null : _toItem(row);
  }

  @override
  Future<void> discard(String itemId, {String? reason}) async {
    await (db.update(db.aiInboxItems)..where(
          (t) =>
              t.id.equals(itemId) & t.status.equals(InboxStatus.pending.name),
        ))
        .write(
          AiInboxItemsCompanion(
            status: Value(InboxStatus.discarded.name),
            note: reason == null ? const Value.absent() : Value(reason),
          ),
        );
  }

  @override
  Future<ConfirmResult> confirm(
    String itemId,
    List<ProposedTransaction> rows,
  ) async {
    final item = await getItem(itemId);

    if (item == null) {
      throw StateError('Inbox item $itemId does not exist');
    }

    if (item.status != InboxStatus.pending) return const ConfirmResult();

    final errors = <int, String>{};
    final accounts = await _loadAccounts();
    final categoryIds = await _loadCategoryIds();

    for (var i = 0; i < rows.length; i++) {
      final error = _validate(rows[i], accounts, categoryIds);
      if (error != null) errors[i] = error;
    }

    final matches = await _findDuplicates(rows, errors.keys.toSet());
    final skippedRows = {for (final m in matches) m.rowIndex};
    final alreadyCreated = item.resultTransactionIds.toSet();

    // Rows matching what this item already created are leftovers of a
    // previous attempt, not duplicates worth reporting.
    final duplicates = [
      for (final m in matches)
        if (!alreadyCreated.contains(m.existingTransactionId)) m,
    ];

    final createdIds = <String>[];

    await db.transaction(() async {
      final tagId = await _getOrCreateInboxTag();

      for (var i = 0; i < rows.length; i++) {
        if (errors.containsKey(i) || skippedRows.contains(i)) continue;

        try {
          await db.transaction(() async {
            final id = await _createTransaction(item, rows[i], tagId);
            createdIds.add(id);
          });
        } catch (e) {
          errors[i] = e.toString();
        }
      }

      final allIds = {...item.resultTransactionIds, ...createdIds}.toList();

      if (item.resultTransactionIds.isEmpty && createdIds.isNotEmpty) {
        await _linkAttachments(createdIds.first, item.attachmentPaths);
      }

      await (db.update(
        db.aiInboxItems,
      )..where((t) => t.id.equals(itemId))).write(
        AiInboxItemsCompanion(
          status: Value(
            errors.isEmpty
                ? InboxStatus.processed.name
                : InboxStatus.pending.name,
          ),
          proposalsJson: Value(_encodeProposals(rows)),
          resultTransactionIdsJson: Value(jsonEncode(allIds)),
        ),
      );
    });

    return ConfirmResult(
      createdIds: createdIds,
      duplicates: duplicates,
      errors: errors,
    );
  }

  @override
  Future<List<DuplicateWarning>> previewDuplicates(
    List<ProposedTransaction> rows,
  ) async {
    final accounts = await _loadAccounts();
    final categoryIds = await _loadCategoryIds();

    return _findDuplicates(rows, {
      for (var i = 0; i < rows.length; i++)
        if (_validate(rows[i], accounts, categoryIds) != null) i,
    });
  }

  Future<AiInboxItemInDB?> _getRow(String id) {
    return (db.select(
      db.aiInboxItems,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Map<String, AccountInDB>> _loadAccounts() async {
    return {for (final a in await db.select(db.accounts).get()) a.id: a};
  }

  Future<Set<String>> _loadCategoryIds() async {
    final ids =
        await (db.selectOnly(db.categories)..addColumns([db.categories.id]))
            .map((r) => r.read(db.categories.id)!)
            .get();
    return ids.toSet();
  }

  /// Returns the message to show for the row, or null if it can be written.
  String? _validate(
    ProposedTransaction row,
    Map<String, AccountInDB> accounts,
    Set<String> categoryIds,
  ) {
    final e = t.ia_inbox.errors;

    if (!row.amount.isFinite || row.amount <= 0) return e.amount;

    if (row.type != TransactionType.expense &&
        row.type != TransactionType.income) {
      return e.type;
    }

    final account = row.accountId == null ? null : accounts[row.accountId];
    if (account == null) return e.account;

    if (row.categoryId == null || !categoryIds.contains(row.categoryId)) {
      return e.category;
    }

    if (account.date.compareTo(row.date) > 0) {
      return t.transaction.form.validators.date_after_account_creation;
    }

    return null;
  }

  /// Duplicates among the rows that passed validation, against what is already
  /// stored and against earlier rows of the same batch. A match with an earlier
  /// row of the batch has an empty existingTransactionId.
  Future<List<DuplicateWarning>> _findDuplicates(
    List<ProposedTransaction> rows,
    Set<int> invalidRows,
  ) async {
    final validIndexes = [
      for (var i = 0; i < rows.length; i++)
        if (!invalidRows.contains(i)) i,
    ];

    if (validIndexes.isEmpty) return const [];

    final candidates = [
      for (final i in validIndexes)
        dedupe.DedupeCandidate(
          date: rows[i].date,
          amount: rows[i].amount,
          accountId: rows[i].accountId!,
          type: rows[i].type,
          title: rows[i].title,
        ),
    ];

    final accountIds = candidates.map((c) => c.accountId).toSet();
    final dates = candidates.map((c) => c.date);
    final from = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final to = dates.reduce((a, b) => a.isAfter(b) ? a : b);

    final stored =
        await (db.select(db.transactions)..where(
              (t) =>
                  t.accountID.isIn(accountIds) &
                  t.type.isIn([
                    TransactionType.expense.databaseValue,
                    TransactionType.income.databaseValue,
                  ]) &
                  t.date.isBiggerOrEqualValue(
                    from.subtract(const Duration(days: 2)),
                  ) &
                  t.date.isSmallerOrEqualValue(to.add(const Duration(days: 2))),
            ))
            .get();

    final existing = [
      for (final tx in stored)
        dedupe.DedupeCandidate(
          id: tx.id,
          date: tx.date,
          amount: tx.value.abs(),
          accountId: tx.accountID,
          type: tx.type,
          title: tx.title ?? '',
        ),
    ];

    return [
      for (final match in findDuplicates(candidates, existing))
        DuplicateWarning(
          rowIndex: validIndexes[match.rowIndex],
          existingTransactionId: match.existingId ?? '',
          reason: match.reason,
        ),
    ];
  }

  Future<String> _getOrCreateInboxTag() async {
    final existing = await (db.select(
      db.tags,
    )..where((t) => t.name.equals(inboxTagName))).getSingleOrNull();

    if (existing != null) return existing.id;

    final maxOrder = db.tags.displayOrder.max();
    final current = await (db.selectOnly(
      db.tags,
    )..addColumns([maxOrder])).map((r) => r.read(maxOrder)).getSingle();

    final id = generateUUID();

    await db
        .into(db.tags)
        .insert(
          TagInDB(
            id: id,
            name: inboxTagName,
            color: _inboxTagColor,
            displayOrder: (current ?? 0) + 1,
          ),
        );

    return id;
  }

  Future<String> _createTransaction(
    InboxItem item,
    ProposedTransaction row,
    String tagId,
  ) async {
    final id = generateUUID();
    final title = row.title.trim();

    await transactions.insertTransaction(
      TransactionInDB(
        id: id,
        date: row.date,
        accountID: row.accountId!,
        categoryID: row.categoryId,
        value: row.type == TransactionType.expense ? -row.amount : row.amount,
        type: row.type,
        title: title.isEmpty ? null : title,
        notes: _notesWithOrigin(item, row),
        isHidden: false,
        status: row.date.isAfter(DateTime.now())
            ? TransactionStatus.pending
            : null,
      ),
    );

    await db
        .into(db.transactionTags)
        .insert(TransactionTag(transactionID: id, tagID: tagId));

    return id;
  }

  Future<void> _linkAttachments(
    String transactionId,
    List<String> paths,
  ) async {
    final now = DateTime.now();

    for (final path in paths) {
      await db
          .into(db.transactionAttachments)
          .insert(
            TransactionAttachmentInDB(
              id: generateUUID(),
              transactionID: transactionId,
              filePath: path,
              createdAt: now,
            ),
          );
    }
  }

  String _notesWithOrigin(InboxItem item, ProposedTransaction row) {
    final prefix = switch (item.source) {
      InboxSource.receipt => 'recibo',
      InboxSource.statement => 'extracto',
      InboxSource.notification => 'aviso',
    };
    final origin = '[origen: $prefix:${item.sourceRef}]';
    final notes = row.notes?.trim() ?? '';

    if (notes.isEmpty) return origin;
    if (notes.endsWith(origin)) return notes;

    return '$notes\n$origin';
  }

  String _encodeProposals(List<ProposedTransaction> rows) =>
      jsonEncode(rows.map((r) => r.toJson()).toList());

  InboxItem _toItem(AiInboxItemInDB row) {
    List<String> strings(String? json) => json == null
        ? const []
        : (jsonDecode(json) as List).cast<String>().toList();

    return InboxItem(
      id: row.id,
      source: InboxSource.values.byName(row.source),
      sourceRef: row.sourceRef,
      status: InboxStatus.values.byName(row.status),
      createdAt: row.createdAt,
      proposals: (jsonDecode(row.proposalsJson) as List)
          .map((j) => ProposedTransaction.fromJson(j as Map<String, dynamic>))
          .toList(),
      rawText: row.rawText,
      attachmentPaths: strings(row.attachmentsJson),
      resultTransactionIds: strings(row.resultTransactionIdsJson),
      note: row.note,
    );
  }
}
