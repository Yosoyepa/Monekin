// Anti-duplicate fingerprint of notices and the rule of budget alerts (T002). Owner: w-avisos.
import 'package:monekin/features_ia/notifications/notification_prefs.dart';

/// Stable key of one notification: app + text + minute it was posted. The same notice delivered twice
/// (the app updates it, the listener reconnects) has the same key; two purchases a minute apart do not.
String noticeFingerprint(
  String package,
  String title,
  String content,
  int postedAtMs,
) {
  final text = '$title\n$content'
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final raw = '$package|$text|${postedAtMs ~/ 60000}';
  // Two FNV-1a 32-bit hashes with different seeds: 64 bits without a crypto dependency.
  int fnv(int seed) {
    var h = seed;
    for (final unit in raw.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  return fnv(0x811c9dc5).toRadixString(16).padLeft(8, '0') +
      fnv(0x2f9be6cd).toRadixString(16).padLeft(8, '0');
}

class NoticeFingerprints {
  NoticeFingerprints(
    this.prefs, {
    DateTime Function()? now,
    this.keepFor = const Duration(days: 7),
    this.maxEntries = 300,
  }) : _now = now ?? DateTime.now;

  final NotificationsPrefs prefs;
  final DateTime Function() _now;
  final Duration keepFor;
  final int maxEntries;

  /// True the first time [fingerprint] is seen (and remembers it); false for a repeat.
  Future<bool> registerIfNew(String fingerprint) async {
    final nowMs = _now().millisecondsSinceEpoch;
    final seen = await prefs.fingerprints();
    seen.removeWhere((_, at) => nowMs - at > keepFor.inMilliseconds);
    if (seen.containsKey(fingerprint)) return false;
    seen[fingerprint] = nowMs;
    while (seen.length > maxEntries) {
      final oldest = seen.entries
          .reduce((a, b) => a.value <= b.value ? a : b)
          .key;
      seen.remove(oldest);
    }
    await prefs.saveFingerprints(seen);
    return true;
  }
}

extension NoticeFingerprintsForget on NoticeFingerprints {
  /// Lets a notice be processed again, e.g. when saving it to the inbox failed.
  Future<void> forget(String fingerprint) async {
    final seen = await prefs.fingerprints();
    if (seen.remove(fingerprint) != null) await prefs.saveFingerprints(seen);
  }
}

enum BudgetAlertLevel {
  /// 80 % of the limit spent.
  warning(80),

  /// The limit is reached or passed.
  exceeded(100);

  const BudgetAlertLevel(this.percent);

  final int percent;
}

/// Which alert a budget deserves given the share of the limit already spent and the highest level
/// already notified in this period. 79 % -> none, 80 % -> warning, 100 % -> exceeded, never repeats.
BudgetAlertLevel? budgetAlertFor(double fractionSpent, int notifiedPercent) {
  const eps = 1e-9;
  if (fractionSpent + eps >= 1 && notifiedPercent < 100) {
    return BudgetAlertLevel.exceeded;
  }
  if (fractionSpent + eps >= 0.8 && notifiedPercent < 80) {
    return BudgetAlertLevel.warning;
  }
  return null;
}

class BudgetAlertTracker {
  BudgetAlertTracker(this.prefs);

  final NotificationsPrefs prefs;

  /// Decides and remembers the alert of one budget. Each level is notified once per budget period, so
  /// checking again the same day (or later in the period) does not repeat it.
  Future<BudgetAlertLevel?> evaluate({
    required String budgetId,
    required DateTime periodStart,
    required double fractionSpent,
  }) async {
    final key = '$budgetId|${periodStart.toIso8601String().substring(0, 10)}';
    final state = await prefs.budgetAlertState();
    final level = budgetAlertFor(fractionSpent, state[key] ?? 0);
    if (level == null) return null;
    state[key] = level.percent;
    await prefs.saveBudgetAlertState(state);
    return level;
  }
}
