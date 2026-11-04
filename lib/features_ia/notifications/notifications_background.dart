// Background task handlers of notifications (T002). Owner: w-avisos. Each returns true when done.
// They run in the workmanager isolate, where `prepareBackgroundIsolate()` has already opened the services.
import 'package:intl/intl.dart';
import 'package:monekin/core/database/services/budget/budget_service.dart';
import 'package:monekin/core/models/budget/target_timeline_status.enum.dart';
import 'package:monekin/features_ia/insights/insights_service.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notification_guards.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

/// Share of a budget limit already spent in its current period.
class BudgetProgress {
  const BudgetProgress({
    required this.id,
    required this.name,
    required this.fraction,
    required this.periodStart,
  });

  final String id;
  final String name;
  final double fraction;
  final DateTime periodStart;
}

Future<List<BudgetProgress>> _activeBudgetsFromDb() async {
  final budgets = await BudgetServive.instance.getBudgets().first;
  final result = <BudgetProgress>[];
  for (final b in budgets) {
    if (b.timelineStatus != TargetTimelineStatus.active) continue;
    result.add(
      BudgetProgress(
        id: b.id,
        name: b.name,
        fraction: await b.percentageAlreadyUsed.first,
        periodStart: b.currentDateRange.start,
      ),
    );
  }
  return result;
}

/// Re-arms the daily reminder (it is lost after a time zone change or an app data wipe).
Future<bool> runDailyReminderTask({
  NotificationsPrefs? prefs,
  PluginLocalNotifier? notifier,
}) async {
  prefs ??= NotificationsPrefs.instance;
  notifier ??= PluginLocalNotifier.instance;
  if (!await prefs.dailyReminderEnabled()) {
    await notifier.cancel(kNotifIdDailyReminder);
    return true;
  }
  final minutes = await prefs.dailyReminderMinutes();
  await notifier.scheduleDaily(
    hour: minutes ~/ 60,
    minute: minutes % 60,
    title: t.ia_notifications.daily_title,
    body: t.ia_notifications.daily_body,
  );
  return true;
}

/// Notifies the budgets that reached 80 % or 100 % of their limit, once per level and period.
Future<bool> runBudgetCheckTask({
  NotificationsPrefs? prefs,
  LocalNotifier? notifier,
  Future<List<BudgetProgress>> Function()? budgets,
}) async {
  prefs ??= NotificationsPrefs.instance;
  notifier ??= PluginLocalNotifier.instance;
  if (!await prefs.budgetAlertsEnabled()) return true;

  final tracker = BudgetAlertTracker(prefs);
  final tr = t.ia_notifications;
  for (final b in await (budgets ?? _activeBudgetsFromDb)()) {
    final level = await tracker.evaluate(
      budgetId: b.id,
      periodStart: b.periodStart,
      fractionSpent: b.fraction,
    );
    if (level == null) continue;
    final percent = (b.fraction * 100).floor();
    final exceeded = level == BudgetAlertLevel.exceeded;
    await notifier.show(
      id: notificationIdFor('budget|${b.id}|${level.percent}'),
      channel: AlertChannel.budget,
      title: exceeded ? tr.budget_exceeded_title : tr.budget_warning_title,
      body: exceeded
          ? tr.budget_exceeded_body(name: b.name, percent: percent)
          : tr.budget_warning_body(name: b.name, percent: percent),
    );
  }
  return true;
}

/// Shows the weekly summary on Mondays (from 9:00), once per week, when there is something to say.
Future<bool> runWeeklySummaryTask({
  NotificationsPrefs? prefs,
  LocalNotifier? notifier,
  DateTime Function()? now,
}) async {
  prefs ??= NotificationsPrefs.instance;
  notifier ??= PluginLocalNotifier.instance;
  final clock = (now ?? DateTime.now)();
  if (!await prefs.weeklySummaryEnabled()) return true;
  if (clock.weekday != DateTime.monday || clock.hour < 9) return true;

  final today = DateFormat('yyyy-MM-dd').format(clock);
  if (await prefs.lastWeeklySummaryDay() == today) return true;

  final summary = await InsightsService.instance.weeklySummary();
  if (summary == null) return true;
  await notifier.show(
    id: kNotifIdWeeklySummary,
    channel: AlertChannel.weekly,
    title: summary.title,
    body: summary.body,
  );
  await prefs.setLastWeeklySummaryDay(today);
  return true;
}

/// Catch-up for notices posted while the app was closed (the plugin only streams to a running app):
/// reads the notifications still in the shade; the fingerprint keeps already seen ones out.
Future<bool> runNoticeScanTask({NotificationProcessor? processor}) async {
  final prefs = NotificationsPrefs.instance;
  if (!await prefs.listenerEnabled() ||
      !await NotificationListenerService.isPermissionGranted()) {
    return true;
  }
  final proc = processor ?? NotificationProcessor();
  // The plugin's own getActiveNotifications() casts a missing field to bool and throws, so the channel is read directly.
  final active =
      await methodeChannel.invokeMethod<List<dynamic>>(
        'getActiveNotifications',
      ) ??
      const [];
  for (final n in active.whereType<Map<dynamic, dynamic>>()) {
    if (n['onGoing'] == true) continue;
    await proc.process(
      RawNotice(
        package: '${n['packageName'] ?? ''}',
        title: '${n['title'] ?? ''}',
        content: '${n['content'] ?? ''}',
        postedAtMs: (n['postTime'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return true;
}
