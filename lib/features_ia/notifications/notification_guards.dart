// Anti-duplicate fingerprint of notices and the rule of budget alerts (T002). Owner: w-avisos.
import 'package:monekin/features_ia/notifications/notification_prefs.dart';

/// Key of one notification: app + the id the system gave it + the exact time the system posted it + its
/// normalized text. The listener and the background scan read the same system notification, so they get the
/// same post time and make one item; a new identical purchase has another post time even when the bank
/// reuses the id, and makes another item.
///
/// Without a post time ([postedAtMs] <= 0) the stamp is the date and time written in the text, if any, and
/// otherwise the minute of [now]: then two deliveries in different minutes count as two notices.
String noticeFingerprint(
  String package,
  int? notificationId,
  String title,
  String content,
  int postedAtMs, {
  required DateTime now,
}) {
  final text = '$title\n$content'
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final stamp = postedAtMs > 0
      ? 'p$postedAtMs'
      : _stampInText(text) ?? 'm${now.millisecondsSinceEpoch ~/ 60000}';
  // Two FNV-1a 32-bit hashes with different seeds: 64 bits without a crypto dependency.
  int fnv(int seed) {
    var h = seed;
    for (final unit in text.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  final hash =
      fnv(0x811c9dc5).toRadixString(16).padLeft(8, '0') +
      fnv(0x2f9be6cd).toRadixString(16).padLeft(8, '0');
  return '$package|${notificationId ?? ''}|$stamp|$hash';
}

/// «15/09/2026 a las 20:35» in the text of a notice, or null when it lacks the date or the time.
String? _stampInText(String text) {
  final date = RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b').firstMatch(text);
  final time = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(text);
  if (date == null || time == null) return null;
  return 'd${date.group(1)}/${date.group(2)}/${date.group(3)}'
      't${time.group(1)}:${time.group(2)}';
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
  ///
  /// With [send], the level is remembered only after [send] finishes; if it throws, the alert stays due
  /// and the error goes up. The whole check runs under the store lock, so two isolates do not both send it.
  Future<BudgetAlertLevel?> evaluate({
    required String budgetId,
    required DateTime periodStart,
    required double fractionSpent,
    Future<void> Function(BudgetAlertLevel level)? send,
  }) {
    final key = '$budgetId|${periodStart.toIso8601String().substring(0, 10)}';
    return prefs.editBudgetAlertState((state) async {
      final level = budgetAlertFor(fractionSpent, state[key] ?? 0);
      if (level == null) return null;
      await send?.call(level);
      state[key] = level.percent;
      return level;
    });
  }
}
