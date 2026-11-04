// Background tasks of the AI features (T002). Owner: w-avisos (workmanager).
// The dispatcher runs in its own isolate, so every task handler must initialize what it needs.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

/// Entry point of the workmanager isolate. Must stay top level.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await prepareBackgroundIsolate();
      return await runBackgroundTask(task);
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
