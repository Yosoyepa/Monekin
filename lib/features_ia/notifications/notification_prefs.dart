// Settings of the notification features (T002). Owner: w-avisos.
// They live in a small JSON file instead of the Monekin database so the listener, the background tasks
// (another isolate) and the settings page read the same values without opening the database.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:monekin/features_ia/notifications/bank_apps.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The stored data cannot be read. It is left as it is, so nothing derived from it (seen notices, alerts
/// already sent) is taken as empty and repeated.
class StoreCorruptedException implements Exception {
  const StoreCorruptedException(this.message);

  final String message;

  @override
  String toString() => 'StoreCorruptedException: $message';
}

/// Reads and writes inside [KeyValueStore.transaction]: no one else touches the store meanwhile.
abstract class KeyValueTxn {
  Future<String?> get(String key);

  Future<void> set(String key, String? value);
}

abstract class KeyValueStore implements KeyValueTxn {
  /// Runs [action] with exclusive access to the store, shared by every isolate. The changes are saved
  /// together when [action] ends; if it throws, nothing is saved.
  Future<T> transaction<T>(Future<T> Function(KeyValueTxn tx) action);

  @override
  Future<String?> get(String key) => transaction((tx) => tx.get(key));

  @override
  Future<void> set(String key, String? value) =>
      transaction((tx) => tx.set(key, value));
}

/// Runs the actions one after another.
class _Mutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

class _MapTxn implements KeyValueTxn {
  _MapTxn(this.data);

  final Map<String, dynamic> data;
  bool changed = false;

  @override
  Future<String?> get(String key) async => data[key] as String?;

  @override
  Future<void> set(String key, String? value) async {
    changed = true;
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
}

class MemoryKeyValueStore extends KeyValueStore {
  final Map<String, String> data = {};
  final _Mutex _mutex = _Mutex();

  @override
  Future<T> transaction<T>(Future<T> Function(KeyValueTxn tx) action) =>
      _mutex.run(() async {
        final tx = _MapTxn({...data});
        final result = await action(tx);
        if (tx.changed) {
          data
            ..clear()
            ..addAll(tx.data.cast<String, String>());
        }
        return result;
      });
}

/// Keeps the values in `finanzas_notifications.json` of the app support directory. The listener, the
/// settings page and the workmanager isolate share it: every access takes an exclusive lock on a `.lock`
/// file, and a save writes a temporary file and renames it over the real one, so a reader never sees half
/// a file.
class FileKeyValueStore extends KeyValueStore {
  FileKeyValueStore([this._fileProvider]);

  final Future<File> Function()? _fileProvider;

  /// The file lock does not exclude two users inside one process on every platform; this does.
  static final Map<String, _Mutex> _mutexes = {};

  Future<File> _file() async {
    if (_fileProvider != null) return _fileProvider();
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'finanzas_notifications.json'));
  }

  Future<Map<String, dynamic>> _read(File f) async {
    if (!await f.exists()) return {};
    try {
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Falls through to the error below.
    }
    debugPrint(
      'Notification settings file is unreadable and was kept: ${f.path}',
    );
    throw StoreCorruptedException('Unreadable settings file ${f.path}');
  }

  @override
  Future<T> transaction<T>(Future<T> Function(KeyValueTxn tx) action) async {
    final file = await _file();
    return _mutexes.putIfAbsent(file.path, _Mutex.new).run(() async {
      await file.parent.create(recursive: true);
      final lockFile = await File(
        '${file.path}.lock',
      ).open(mode: FileMode.append);
      try {
        await lockFile.lock(FileLock.blockingExclusive);
        final tx = _MapTxn(await _read(file));
        final result = await action(tx);
        if (tx.changed) {
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(jsonEncode(tx.data), flush: true);
          await temp.rename(file.path);
        }
        return result;
      } finally {
        await lockFile.close();
      }
    });
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

  /// A missing key is an empty map; one that cannot be decoded is an error, never an empty map.
  static Map<String, int> _decodeIntMap(String? raw) {
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as int),
      );
    } catch (_) {
      throw const StoreCorruptedException('Unreadable saved state');
    }
  }

  Future<Map<String, int>> _intMap(String key) async =>
      _decodeIntMap(await store.get(key));

  /// Reads the map, lets [change] edit it and saves it, all under the store lock. If [change] throws,
  /// nothing is saved.
  Future<T> _editIntMap<T>(
    String key,
    FutureOr<T> Function(Map<String, int> map) change,
  ) => store.transaction((tx) async {
    final map = _decodeIntMap(await tx.get(key));
    final before = jsonEncode(map);
    final result = await change(map);
    final after = jsonEncode(map);
    if (after != before) await tx.set(key, after);
    return result;
  });

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

  /// Edits the alert state under the store lock (see [KeyValueStore.transaction]).
  Future<T> editBudgetAlertState<T>(
    FutureOr<T> Function(Map<String, int> state) change,
  ) => _editIntMap(_kAlertState, change);

  /// Notice fingerprint -> epoch millis when it was seen.
  Future<Map<String, int>> fingerprints() => _intMap(_kFingerprints);

  Future<void> saveFingerprints(Map<String, int> v) =>
      store.set(_kFingerprints, jsonEncode(v));

  /// Edits the fingerprints under the store lock (see [KeyValueStore.transaction]).
  Future<T> editFingerprints<T>(
    FutureOr<T> Function(Map<String, int> seen) change,
  ) => _editIntMap(_kFingerprints, change);
}
