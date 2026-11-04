// Settings of the notification features (T002). Owner: w-avisos.
// They live in a small JSON file instead of the Monekin database so the listener, the background tasks
// (another isolate) and the settings page read the same values without opening the database.
import 'dart:convert';
import 'dart:io';

import 'package:monekin/features_ia/notifications/bank_apps.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class KeyValueStore {
  Future<String?> get(String key);

  Future<void> set(String key, String? value);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
}

/// Keeps the values in `finanzas_notifications.json` of the app support directory.
class FileKeyValueStore implements KeyValueStore {
  FileKeyValueStore([this._fileProvider]);

  final Future<File> Function()? _fileProvider;

  Future<File> _file() async {
    if (_fileProvider != null) return _fileProvider();
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'finanzas_notifications.json'));
  }

  Future<Map<String, dynamic>> _read(File f) async {
    try {
      if (!await f.exists()) return {};
      final decoded = jsonDecode(await f.readAsString());
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<String?> get(String key) async =>
      (await _read(await _file()))[key] as String?;

  @override
  Future<void> set(String key, String? value) async {
    final f = await _file();
    final all = await _read(f);
    if (value == null) {
      all.remove(key);
    } else {
      all[key] = value;
    }
    await f.writeAsString(jsonEncode(all), flush: true);
  }
}

class NotificationsPrefs {
  NotificationsPrefs([KeyValueStore? store])
    : store = store ?? FileKeyValueStore();

  /// Used by the listener, the settings page and the background tasks.
  static NotificationsPrefs instance = NotificationsPrefs();

  final KeyValueStore store;

  static const _kListener = 'listener_enabled';
  static const _kPackages = 'watched_packages';
  static const _kDaily = 'daily_enabled';
  static const _kDailyMinutes = 'daily_minutes';
  static const _kBudget = 'budget_alerts';
  static const _kWeekly = 'weekly_enabled';
  static const _kWeeklyLast = 'weekly_last_day';
  static const _kAlertState = 'budget_alert_state';
  static const _kFingerprints = 'fingerprints';

  Future<bool> _bool(String key, bool def) async =>
      switch (await store.get(key)) {
        'true' => true,
        'false' => false,
        _ => def,
      };

  Future<Map<String, int>> _intMap(String key) async {
    try {
      final raw = await store.get(key);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as int),
      );
    } catch (_) {
      return {};
    }
  }

  Future<bool> listenerEnabled() => _bool(_kListener, false);

  Future<void> setListenerEnabled(bool v) => store.set(_kListener, '$v');

  Future<Set<String>> watchedPackages() async {
    final raw = await store.get(_kPackages);
    if (raw == null) return defaultWatchedPackages();
    return (jsonDecode(raw) as List).cast<String>().toSet();
  }

  Future<void> setWatchedPackages(Set<String> packages) =>
      store.set(_kPackages, jsonEncode(packages.toList()..sort()));

  Future<bool> dailyReminderEnabled() => _bool(_kDaily, false);

  Future<void> setDailyReminderEnabled(bool v) => store.set(_kDaily, '$v');

  /// Minutes since midnight; 20:00 by default.
  Future<int> dailyReminderMinutes() async =>
      int.tryParse(await store.get(_kDailyMinutes) ?? '') ?? 20 * 60;

  Future<void> setDailyReminderMinutes(int v) =>
      store.set(_kDailyMinutes, '$v');

  Future<bool> budgetAlertsEnabled() => _bool(_kBudget, true);

  Future<void> setBudgetAlertsEnabled(bool v) => store.set(_kBudget, '$v');

  Future<bool> weeklySummaryEnabled() => _bool(_kWeekly, false);

  Future<void> setWeeklySummaryEnabled(bool v) => store.set(_kWeekly, '$v');

  /// Day (yyyy-MM-dd) the last weekly summary was shown, or null.
  Future<String?> lastWeeklySummaryDay() => store.get(_kWeeklyLast);

  Future<void> setLastWeeklySummaryDay(String day) =>
      store.set(_kWeeklyLast, day);

  /// `<budgetId>|<period start>` -> highest level (80 or 100) already notified.
  Future<Map<String, int>> budgetAlertState() => _intMap(_kAlertState);

  Future<void> saveBudgetAlertState(Map<String, int> state) =>
      store.set(_kAlertState, jsonEncode(state));

  /// Notice fingerprint -> epoch millis when it was seen.
  Future<Map<String, int>> fingerprints() => _intMap(_kFingerprints);

  Future<void> saveFingerprints(Map<String, int> v) =>
      store.set(_kFingerprints, jsonEncode(v));
}
