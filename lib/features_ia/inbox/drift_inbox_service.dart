// Drift implementation of the AI inbox (T002). Owner: w-inbox.
// The only code that writes transactions coming from the AI: `confirm`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/transaction/transaction_status.enum.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/utils/uuid.dart';
import 'package:monekin/features_ia/core/dedupe/dedupe.dart' as dedupe;
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:uuid/uuid.dart';

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

  static final Map<String, Future<void>> _confirmLocks = {};

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

  /// Drops the processed and discarded items older than [maxAge], by creation time
  /// (the table keeps no decision time). Photos of discarded items are deleted; photos
  /// of processed items stay, because transactions hold them. Returns the items dropped.
  Future<int> purgeOld({
    required DateTime now,
    Duration maxAge = const Duration(days: 30),
  }) async {
    final cutoff = now.subtract(maxAge);
    final old =
        await (db.select(db.aiInboxItems)..where(
              (t) =>
                  t.createdAt.isSmallerThanValue(cutoff) &
                  t.status.isIn([
                    InboxStatus.processed.name,
                    InboxStatus.discarded.name,
                  ]),
            ))
            .get();
    if (old.isEmpty) return 0;

    for (final row in old.where(
      (row) => row.status == InboxStatus.discarded.name,
    )) {
      final photos = (jsonDecode(row.attachmentsJson ?? '[]') as List)
          .cast<String>();
      for (final path in photos) {
        final photo = File(path);
        if (await photo.exists()) await photo.delete();
      }
    }

    await (db.delete(
      db.aiInboxItems,
    )..where((t) => t.id.isIn(old.map((row) => row.id)))).go();

    return old.length;
  }

  @override
  Future<ConfirmResult> confirm(
    String itemId,
    List<ProposedTransaction> rows,
  ) async {
    final previous = _confirmLocks[itemId];
    final done = Completer<void>();
    _confirmLocks[itemId] = done.future;
    if (previous != null) await previous;
    try {
      return await db.transaction(() async {
        final item = await getItem(itemId);
        if (item == null) throw StateError('Inbox item $itemId does not exist');
        if (item.status != InboxStatus.pending) return const ConfirmResult();

        // Older partial items have no row-to-transaction mapping. Do not guess.
        if (item.resultTransactionIds.isNotEmpty &&
            !item.proposals.any((p) => p.status == ProposalStatus.created)) {
          return ConfirmResult(
            errors: {
              for (var i = 0; i < rows.length; i++)
                i: t.ia_inbox.errors.legacy_partial,
            },
          );
        }

        final stored = {for (final p in item.proposals) p.id: p};
        final effective = <ProposedTransaction>[];
        final seen = <String>{};
        for (final row in rows) {
          if (!seen.add(row.id)) continue;
          final prior = stored[row.id];
          if (prior != null &&
              (prior.status == ProposalStatus.created ||
                  prior.status == ProposalStatus.skippedDuplicate)) {
            effective.add(prior);
          } else {
            final copy = ProposedTransaction.fromJson(row.toJson());
            copy.status = ProposalStatus.pending;
            copy.transactionId = null;
            copy.errorMessage = null;
            if (row.duplicateChoice != null) {
              copy.allowDuplicate = row.duplicateChoice!;
            }
            effective.add(copy);
          }
        }
        for (final prior in item.proposals) {
          if (!seen.contains(prior.id) &&
              (prior.status == ProposalStatus.created ||
                  prior.status == ProposalStatus.skippedDuplicate)) {
            effective.add(prior);
          }
        }
        final accounts = await _loadAccounts();
        final categories = await _loadCategories();
        final errors = <int, String>{};
        final inactive = <int>{};
        for (var i = 0; i < effective.length; i++) {
          final row = effective[i];
          if (row.status == ProposalStatus.created ||
              row.status == ProposalStatus.skippedDuplicate) {
            inactive.add(i);
            continue;
          }
          final error = _validate(row, accounts, categories);
          if (error != null) errors[i] = error;
        }
        final matches = await _findDuplicates(effective, {
          ...errors.keys,
          ...inactive,
        }, excludedIds: item.resultTransactionIds.toSet());
        final skipped = <DuplicateWarning>[];
        for (final match in matches) {
          if (!effective[match.rowIndex].allowForReason(match.reason)) {
            skipped.add(match);
          }
        }
        final skippedRows = {for (final match in skipped) match.rowIndex};
        final createdIds = <String>[];
        final tagId = await _getOrCreateInboxTag();
        for (var i = 0; i < effective.length; i++) {
          if (inactive.contains(i)) continue;
          final row = effective[i];
          if (errors.containsKey(i)) {
            row.status = ProposalStatus.error;
            row.errorMessage = errors[i];
          } else if (skippedRows.contains(i)) {
            row.status = ProposalStatus.skippedDuplicate;
            row.errorMessage = skipped
                .firstWhere((m) => m.rowIndex == i)
                .reason;
          } else {
            try {
              final id = await db.transaction(
                () => _createTransaction(item, row, tagId),
              );
              createdIds.add(id);
              row.status = ProposalStatus.created;
              row.transactionId = id;
              row.errorMessage = null;
            } catch (e) {
              errors[i] = e.toString();
              row.status = ProposalStatus.error;
              row.errorMessage = errors[i];
            }
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
            proposalsJson: Value(_encodeProposals(effective)),
            resultTransactionIdsJson: Value(jsonEncode(allIds)),
          ),
        );
        return ConfirmResult(
          createdIds: createdIds,
          duplicates: skipped,
          errors: errors,
        );
      });
    } finally {
      if (identical(_confirmLocks[itemId], done.future)) {
        unawaited(_confirmLocks.remove(itemId));
      }
      done.complete();
    }
  }

  @override
  Future<List<DuplicateWarning>> previewDuplicates(
    List<ProposedTransaction> rows,
  ) async {
    final accounts = await _loadAccounts();
    final categoryIds = await _loadCategories();

    return _findDuplicates(
      rows,
      {
        for (var i = 0; i < rows.length; i++)
          if (_validate(rows[i], accounts, categoryIds, checkCategory: false) !=
                  null ||
              rows[i].status == ProposalStatus.created ||
              rows[i].status == ProposalStatus.skippedDuplicate)
            i,
      },
      excludedIds: {
        for (final row in rows)
          if (row.transactionId != null) row.transactionId!,
      },
    );
  }

  Future<AiInboxItemInDB?> _getRow(String id) {
    return (db.select(
      db.aiInboxItems,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Map<String, AccountInDB>> _loadAccounts() async {
    return {for (final a in await db.select(db.accounts).get()) a.id: a};
  }

  Future<Map<String, CategoryType?>> _loadCategories() async {
    final categories = {
      for (final c in await db.select(db.categories).get()) c.id: c,
    };
    return {
      for (final c in categories.values)
        c.id: c.type ?? categories[c.parentCategoryID]?.type,
    };
  }

  /// Returns the message to show for the row, or null if it can be written.
  /// [checkCategory] is off for the duplicate preview, which does not need one.
  String? _validate(
    ProposedTransaction row,
    Map<String, AccountInDB> accounts,
    Map<String, CategoryType?> categoryIds, {
    bool checkCategory = true,
  }) {
    final e = t.ia_inbox.errors;

    if (!row.amount.isFinite || row.amount <= 0) return e.amount;

    if (row.type != TransactionType.expense &&
        row.type != TransactionType.income) {
      return e.type;
    }

    final account = row.accountId == null ? null : accounts[row.accountId];
    if (account == null) return e.account;
    if (account.isSaving) return e.saving_account;

    if (checkCategory &&
        (row.categoryId == null ||
            !(categoryIds[row.categoryId]?.matchWithTransactionType(row.type) ??
                false))) {
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
    Set<int> invalidRows, {
    Set<String> excludedIds = const {},
  }) async {
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
        if (!excludedIds.contains(tx.id))
          dedupe.DedupeCandidate(
            id: tx.id,
            date: tx.date,
            amount: tx.value.abs(),
            accountId: tx.accountID,
            type: tx.type,
            title: tx.title ?? '',
          ),
    ];

    final matches = findDuplicates(candidates, existing);
    final matched = {for (final match in matches) match.rowIndex};
    final warnings = [
      for (final match in matches)
        DuplicateWarning(
          rowIndex: validIndexes[match.rowIndex],
          existingTransactionId: match.existingId ?? '',
          reason: match.reason,
        ),
    ];
    for (var i = 0; i < validIndexes.length; i++) {
      if (matched.contains(i)) continue;
      final index = validIndexes[i];
      for (var j = 0; j < index; j++) {
        final prior = rows[j];
        if (prior.status != ProposalStatus.created || prior.accountId == null) {
          continue;
        }
        final earlier = dedupe.DedupeCandidate(
          date: prior.date,
          amount: prior.amount,
          accountId: prior.accountId!,
          type: prior.type,
          title: prior.title,
        );
        if (findDuplicates([
          earlier,
          candidates[i],
        ], const []).any((m) => m.rowIndex == 1)) {
          warnings.add(
            DuplicateWarning(
              rowIndex: index,
              existingTransactionId: '',
              reason: dedupe.duplicateInBatch,
            ),
          );
          break;
        }
      }
    }
    return warnings;
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
      proposals: [
        for (final (index, json)
            in (jsonDecode(row.proposalsJson) as List).indexed)
          ProposedTransaction.fromJson({
            ...(json as Map<String, dynamic>),
            'id':
                json['id'] ??
                const Uuid().v5(
                  Namespace.url.value,
                  'monekin-inbox:${row.id}:$index',
                ),
          }),
      ],
      rawText: row.rawText,
      attachmentPaths: strings(row.attachmentsJson),
      resultTransactionIds: strings(row.resultTransactionIdsJson),
      note: row.note,
    );
  }
}
