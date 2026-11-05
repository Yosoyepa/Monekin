// Background tasks of the AI features (T002). Owner: w-avisos (workmanager).
// The dispatcher runs in its own isolate, so every task handler must initialize what it needs.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/restore_journal.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:monekin/core/database/services/user-setting/user_setting_service.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_factory.dart';
import 'package:monekin/features_ia/google/google_background.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';
import 'package:monekin/features_ia/google/google_backup_service_factory.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/inbox/inbox_service_factory.dart';
import 'package:monekin/features_ia/insights/insights_service.dart';
import 'package:monekin/features_ia/insights/insights_service_factory.dart';
import 'package:monekin/features_ia/notifications/notifications_background.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:workmanager/workmanager.dart';

const kTaskDailyReminder = 'finanzas.dailyReminder';
const kTaskBudgetCheck = 'finanzas.budgetCheck';
const kTaskWeeklySummary = 'finanzas.weeklySummary';
const kTaskDriveBackup = 'finanzas.driveBackup';

/// Reads the notices still in the shade, for those posted while the app was closed.
const kTaskNoticeScan = 'finanzas.noticeScan';

/// Runs one background task by name. Returns true when it finished (workmanager convention).
Future<bool> runBackgroundTask(String task) async {
  switch (task) {
    case kTaskDailyReminder:
      return runDailyReminderTask();
    case kTaskBudgetCheck:
      return runBudgetCheckTask();
    case kTaskWeeklySummary:
      return runWeeklySummaryTask();
    case kTaskNoticeScan:
      return runNoticeScanTask();
    case kTaskDriveBackup:
      return runDriveBackupTask();
  }
  return true;
}

/// Runs one workmanager execution of [task], unless a restore is running: the lock is
/// held, or its marker or set-aside database is on disk (files, so visible from any
/// isolate). Then it opens nothing, not even [AppDB], and returns false so workmanager
/// tries again later. The run raises its flag before anything else, so a restore waits
/// for it, and it closes the database before it lowers the flag. The parameters are for
/// tests.
Future<bool> executeBackgroundTask(
  String task, {
  Future<String> Function()? databasePath,
  Future<void> Function()? prepare,
  Future<bool> Function(String task)? run,
  Future<void> Function()? close,
}) async {
  final dbPath = await (databasePath ?? _liveDatabasePath)();
  final flag = BackgroundRunFlag.raise(dbPath);
  try {
    debugPrint('Background task $task checking for a restore');
    if (RestoreJournal.leftInFlux(dbPath) || await RestoreLock.isHeld(dbPath)) {
      debugPrint('Background task $task skipped: a restore is running');
      return false;
    }
    await (prepare ?? prepareBackgroundIsolate)();
    return await (run ?? runBackgroundTask)(task);
  } finally {
    // Closing a database that was never opened does nothing. If the close throws, the
    // flag stays: the restores of this process wait for it and fail until it ends, which
    // is safer than moving the files under a connection that may still be open.
    await (close ?? _closeAppDatabase)();
    flag.lower();
  }
}

Future<void> _closeAppDatabase() => AppDB.instance.close();

Future<String> _liveDatabasePath() {
  WidgetsFlutterBinding.ensureInitialized();
  return appDatabasePath();
}

/// Entry point of the workmanager isolate. Must stay top level.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  isBackgroundIsolate = true;
  Workmanager().executeTask((task, inputData) async {
    try {
      return await executeBackgroundTask(task);
    } catch (e) {
      debugPrint('Background task $task failed: $e');
      return false;
    }
  });
}

/// Opens in the background isolate what the tasks use: the Monekin settings (language, database) and the
/// service implementations that `initFeaturesIa()` installs in the main isolate.
Future<void> prepareBackgroundIsolate() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserSettingService.instance.initializeGlobalStateMap();
  AiService.instance = createAiService();
  InboxService.instance = createInboxService();
  InsightsService.instance = createInsightsService();
  GoogleBackupService.instance = createGoogleBackupService();

  final lang = appStateSettings[SettingKey.appLanguage];
  if (lang != null && lang.isNotEmpty) {
    await LocaleSettings.setLocaleRaw(lang);
  } else {
    await LocaleSettings.useDeviceLocale();
  }
}

bool get _supported => !kIsWeb && Platform.isAndroid;

/// Initializes workmanager with the dispatcher.
Future<void> initBackgroundTasks() async {
  if (!_supported) return;
  await Workmanager().initialize(backgroundDispatcher);
}

/// Schedules or cancels a periodic task. Used by the reminders and by w-google for the daily Drive backup.
/// Android runs a periodic task at most every 15 minutes; calling it again updates the schedule.
Future<void> schedulePeriodicTask(String task, Duration every) async {
  if (!_supported) return;
  await Workmanager().registerPeriodicTask(
    task,
    task,
    frequency: every,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: task == kTaskDriveBackup
        ? Constraints(networkType: NetworkType.connected)
        : null,
  );
}

Future<void> cancelBackgroundTask(String task) async {
  if (!_supported) return;
  await Workmanager().cancelByUniqueName(task);
}
