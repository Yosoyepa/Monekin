// Duplicate detection (T002). Owner: w-utils. Used by the inbox before creating transactions.
// Rules from T001 (pkg/aiimport/dedupe.go and the H1 fix): same account, same type, same amount,
// dates at most one day apart and normalized titles that contain each other. When either title
// normalizes to empty, it is a duplicate only when both are empty and the calendar day matches.
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';

class DedupeCandidate {
  const DedupeCandidate({
    required this.date,
    required this.amount,
    required this.accountId,
    required this.type,
    required this.title,
    this.id,
  });

  final DateTime date;
  final double amount;
  final String accountId;
  final TransactionType type;
  final String title;

  /// Id of an existing transaction; null for a new row.
  final String? id;
}

class DedupeMatch {
  const DedupeMatch({required this.rowIndex, this.existingId, this.otherRowIndex, required this.reason});

  final int rowIndex;

  /// Set when the row matches an existing transaction.
  final String? existingId;

  /// Set when the row matches an earlier row of the same batch.
  final int? otherRowIndex;
  final String reason;
}

/// Normalizes a title for comparison: lowercase, no accents, no punctuation,
/// collapsed spaces, and without the `[origen: ...]` suffix.
String normalizeTitle(String title) {
  throw UnimplementedError('normalizeTitle is implemented by w-utils');
}

/// Returns one match per row of [rows] that duplicates an [existing] transaction
/// or an earlier row of the same batch.
List<DedupeMatch> findDuplicates(List<DedupeCandidate> rows, List<DedupeCandidate> existing) {
  throw UnimplementedError('findDuplicates is implemented by w-utils');
}
