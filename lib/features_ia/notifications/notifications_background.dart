// Background task handlers of notifications (T002). Owner: w-avisos. Each returns true when done.
Future<bool> runDailyReminderTask() async => true;

Future<bool> runBudgetCheckTask() async => true;

Future<bool> runWeeklySummaryTask() async => true;
