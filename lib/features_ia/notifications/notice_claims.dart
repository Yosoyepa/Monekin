// Claims of bank notices (T002). Owner: w-avisos.
// The listener and the background scan can read the same notice at the same time, from different isolates.
// Whoever inserts its fingerprint first owns the notice; the other one sees a duplicate.
import 'package:drift/drift.dart';
import 'package:monekin/core/database/app_db.dart';

/// Claims older than this are dropped: the notice is long gone from the shade.
const kNoticeClaimKeepFor = Duration(days: 30);

abstract interface class NoticeClaims {
  /// True for the one caller that takes [fingerprint] first; false for every later one.
  Future<bool> claim(String fingerprint, DateTime now);

  /// Gives the notice back, e.g. when saving it to the inbox failed, so it can be processed again.
  Future<void> release(String fingerprint);
}

/// Kept in the Monekin database: an `INSERT OR IGNORE` on the primary key is atomic for every connection
/// to the file, so two isolates cannot both see the notice as new.
class DriftNoticeClaims implements NoticeClaims {
  DriftNoticeClaims(this.db);

  final AppDB db;

  @override
  Future<bool> claim(String fingerprint, DateTime now) async {
    await _retryBusy(
      () => db.customUpdate(
        'DELETE FROM ai_notice_claims WHERE createdAt < ?',
        variables: [Variable<DateTime>(now.subtract(kNoticeClaimKeepFor))],
        updates: {db.aiNoticeClaims},
      ),
    );
    final inserted = await _retryBusy(
      () => db.customUpdate(
        'INSERT OR IGNORE INTO ai_notice_claims (fingerprint, createdAt) VALUES (?, ?)',
        variables: [Variable<String>(fingerprint), Variable<DateTime>(now)],
        updates: {db.aiNoticeClaims},
      ),
    );
    return inserted == 1;
  }

  @override
  Future<void> release(String fingerprint) async {
    await _retryBusy(
      () => db.customUpdate(
        'DELETE FROM ai_notice_claims WHERE fingerprint = ?',
        variables: [Variable<String>(fingerprint)],
        updates: {db.aiNoticeClaims},
      ),
    );
  }

  /// Another isolate writing at the same moment makes SQLite answer «database is locked»: try again shortly.
  Future<T> _retryBusy<T>(Future<T> Function() action) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await action();
      } catch (e) {
        final busy = RegExp(
          r'database (table )?is locked|SQLITE_BUSY',
          caseSensitive: false,
        ).hasMatch('$e');
        if (!busy || attempt >= 40) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}

/// In memory, for tests and previews.
class MemoryNoticeClaims implements NoticeClaims {
  final Map<String, DateTime> claimed = {};

  @override
  Future<bool> claim(String fingerprint, DateTime now) async {
    claimed.removeWhere(
      (_, at) => at.isBefore(now.subtract(kNoticeClaimKeepFor)),
    );
    if (claimed.containsKey(fingerprint)) return false;
    claimed[fingerprint] = now;
    return true;
  }

  @override
  Future<void> release(String fingerprint) async => claimed.remove(fingerprint);
}
