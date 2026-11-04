// Contract of the AI inbox (T002). Owner: w-inbox.
// Receipts, statements and bank notifications never create transactions
// directly: they add an [InboxDraft]; the user confirms it in the review page.
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/utils/uuid.dart';

enum InboxSource { receipt, statement, notification }

enum InboxStatus { pending, processed, discarded }

enum ProposalStatus { pending, created, skippedDuplicate, error }

/// One transaction proposed by the AI or by a bank-notification template.
class ProposedTransaction {
  ProposedTransaction({
    required this.date,
    required this.title,
    required this.amount,
    this.type = TransactionType.expense,
    this.categoryId,
    this.accountId,
    this.notes,
    this.warning,
    bool? allowDuplicate,
    String? id,
    this.status = ProposalStatus.pending,
    this.transactionId,
    this.errorMessage,
  }) : id = id ?? generateUUID(),
       _allowDuplicate = allowDuplicate;

  final String id;
  ProposalStatus status;
  String? transactionId;
  String? errorMessage;

  DateTime date;

  /// Merchant or short description, e.g. «KFC».
  String title;

  /// Always positive; [type] says whether it is an expense or an income.
  double amount;

  /// Only [TransactionType.expense] or [TransactionType.income].
  TransactionType type;

  /// Must be an existing Monekin category id (or null for the user to choose).
  String? categoryId;

  /// Must be an existing Monekin account id (or null for the user to choose).
  String? accountId;

  String? notes;

  /// Shown in the review page, e.g. «No se leyó el comercio».
  String? warning;

  /// The user chose to create this row even though it looks like a duplicate.
  bool? _allowDuplicate;
  bool get allowDuplicate => _allowDuplicate ?? false;
  bool? get duplicateChoice => _allowDuplicate;
  set allowDuplicate(bool value) => _allowDuplicate = value;
  bool allowForReason(String reason) =>
      _allowDuplicate ?? reason == 'duplicate_in_batch';

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.name,
    'transactionId': transactionId,
    'errorMessage': errorMessage,
    'date': date.toIso8601String(),
    'title': title,
    'amount': amount,
    'type': type.databaseValue,
    'categoryId': categoryId,
    'accountId': accountId,
    'notes': notes,
    'warning': warning,
  };

  static ProposedTransaction fromJson(Map<String, dynamic> j) =>
      ProposedTransaction(
        id: j['id'] as String?,
        status: ProposalStatus.values.byName(
          j['status'] as String? ?? 'pending',
        ),
        transactionId: j['transactionId'] as String?,
        errorMessage: j['errorMessage'] as String?,
        date: DateTime.parse(j['date'] as String),
        title: j['title'] as String,
        amount: (j['amount'] as num).toDouble(),
        type: TransactionType.values.firstWhere(
          (t) => t.databaseValue == j['type'],
          orElse: () => TransactionType.expense,
        ),
        categoryId: j['categoryId'] as String?,
        accountId: j['accountId'] as String?,
        notes: j['notes'] as String?,
        warning: j['warning'] as String?,
      );
}

class InboxDraft {
  InboxDraft({
    required this.source,
    required this.sourceRef,
    required this.proposals,
    this.rawText,
    this.attachmentPaths = const [],
    this.note,
  });

  final InboxSource source;

  /// File name, statement label (`bancolombia-2026-10`) or Android package of the bank app.
  final String sourceRef;

  final List<ProposedTransaction> proposals;

  /// Text the proposals came from (notification text, extracted statement text).
  final String? rawText;

  /// Files kept with the item, e.g. the receipt photo (app documents dir).
  final List<String> attachmentPaths;

  /// Free text for the user, e.g. reconciliation result of a statement.
  final String? note;
}

class InboxItem {
  InboxItem({
    required this.id,
    required this.source,
    required this.sourceRef,
    required this.status,
    required this.createdAt,
    required this.proposals,
    this.rawText,
    this.attachmentPaths = const [],
    this.resultTransactionIds = const [],
    this.note,
  });

  final String id;
  final InboxSource source;
  final String sourceRef;
  final InboxStatus status;
  final DateTime createdAt;
  final List<ProposedTransaction> proposals;
  final String? rawText;
  final List<String> attachmentPaths;
  final List<String> resultTransactionIds;
  final String? note;
}

class DuplicateWarning {
  const DuplicateWarning({
    required this.rowIndex,
    required this.existingTransactionId,
    required this.reason,
  });

  final int rowIndex;
  final String existingTransactionId;
  final String reason;
}

class ConfirmResult {
  const ConfirmResult({
    this.createdIds = const [],
    this.duplicates = const [],
    this.errors = const {},
  });

  final List<String> createdIds;

  /// Rows skipped because they already exist.
  final List<DuplicateWarning> duplicates;

  /// Row index -> error shown to the user. The item stays pending while any row has an error.
  final Map<int, String> errors;
}
