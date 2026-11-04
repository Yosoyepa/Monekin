// Background tasks of the AI features (T002). Owner: w-avisos (workmanager).
// The dispatcher runs in its own isolate, so every task handler must initialize what it needs.
import 'package:monekin/features_ia/google/google_background.dart';
import 'package:monekin/features_ia/notifications/notifications_background.dart';

const kTaskDailyReminder = 'finanzas.dailyReminder';
const kTaskBudgetCheck = 'finanzas.budgetCheck';
const kTaskWeeklySummary = 'finanzas.weeklySummary';
const kTaskDriveBackup = 'finanzas.driveBackup';

/// Runs one background task by name. Returns true when it finished (workmanager convention).
Future<bool> runBackgroundTask(String task) async {
  switch (task) {
    case kTaskDailyReminder:
      return runDailyReminderTask();
    case kTaskBudgetCheck:
      return runBudgetCheckTask();
    case kTaskWeeklySummary:
      return runWeeklySummaryTask();
    case kTaskDriveBackup:
      return runDriveBackupTask();
  }
  return true;
}

/// Initializes workmanager with the dispatcher. Implemented by w-avisos.
Future<void> initBackgroundTasks() async {}

/// Schedules or cancels a periodic task. Implemented by w-avisos; w-google uses it for the daily Drive backup.
Future<void> schedulePeriodicTask(String task, Duration every) async {}

Future<void> cancelBackgroundTask(String task) async {}
