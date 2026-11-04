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
  const DedupeMatch({
    required this.rowIndex,
    this.existingId,
    this.otherRowIndex,
    required this.reason,
  });

  final int rowIndex;

  /// Set when the row matches an existing transaction.
  final String? existingId;

  /// Set when the row matches an earlier row of the same batch.
  final int? otherRowIndex;

  /// `existing` or `batch`.
  final String reason;
}

const _duplicateWindow = Duration(days: 1);

final _originSuffix = RegExp(r'\s*\[origen:[^\]]*\]\s*$');

final _alphanumeric = RegExp(r'^[a-z0-9]$');

// Lowercase Latin-1 letters and the base letter that NFD leaves before the accent.
// Other letters (like `ø` or `ß`) and punctuation separate words.
const _accentedLetters = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
const _baseLetters = 'aaaaaaceeeeiiiinooooouuuuyy';
final _baseOf = {
  for (var i = 0; i < _accentedLetters.length; i++)
    _accentedLetters[i]: _baseLetters[i],
};

/// Normalizes a title for comparison: lowercase, no accents, no punctuation,
/// collapsed spaces, and without the `[origen: ...]` suffix.
String normalizeTitle(String title) {
  final text = title.replaceAll(_originSuffix, '').toLowerCase();
  final buffer = StringBuffer();
  var wordEnded = false;

  for (final char in text.split('')) {
    final letter = _baseOf[char] ?? char;

    if (_alphanumeric.hasMatch(letter)) {
      if (wordEnded && buffer.isNotEmpty) buffer.write(' ');
      buffer.write(letter);
      wordEnded = false;
    } else if (!_isCombiningMark(letter)) {
      wordEnded = true;
    }
  }

  return buffer.toString();
}

/// Returns one match per row of [rows] that duplicates an [existing] transaction or an earlier row of the same batch.
/// Each existing transaction matches at most one row. A batch row only matches an earlier row that is not a duplicate itself.
List<DedupeMatch> findDuplicates(
  List<DedupeCandidate> rows,
  List<DedupeCandidate> existing,
) {
  final matches = <DedupeMatch>[];
  final unclaimed = List.of(existing);
  final kept = <int>[];

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final existingIndex = unclaimed.indexWhere((e) => _isDuplicate(row, e));

    if (existingIndex >= 0) {
      matches.add(
        DedupeMatch(
          rowIndex: i,
          existingId: unclaimed.removeAt(existingIndex).id,
          reason: 'existing',
        ),
      );
      continue;
    }

    final keptIndex = kept.indexWhere((j) => _isDuplicate(row, rows[j]));

    if (keptIndex >= 0) {
      matches.add(
        DedupeMatch(
          rowIndex: i,
          otherRowIndex: kept[keptIndex],
          reason: 'batch',
        ),
      );
    } else {
      kept.add(i);
    }
  }

  return matches;
}

bool _isDuplicate(DedupeCandidate a, DedupeCandidate b) {
  if (a.accountId != b.accountId || a.type != b.type) return false;
  if (_cents(a.amount) != _cents(b.amount)) return false;
  if (a.date.difference(b.date).abs() > _duplicateWindow) return false;

  final titleA = _titleKey(a.title);
  final titleB = _titleKey(b.title);

  if (titleA.isEmpty || titleB.isEmpty) {
    return titleA.isEmpty && titleB.isEmpty && _sameCalendarDay(a.date, b.date);
  }

  return titleA.contains(titleB) || titleB.contains(titleA);
}

// Words joined without spaces, the key that T001 compares (`NormalizeComment`)
String _titleKey(String title) => normalizeTitle(title).replaceAll(' ', '');

int _cents(double amount) => (amount * 100).round();

bool _sameCalendarDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();

  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

bool _isCombiningMark(String letter) {
  final code = letter.codeUnitAt(0);

  return code >= 0x300 && code <= 0x36F;
}
