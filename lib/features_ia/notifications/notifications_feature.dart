// Startup hook of bank-notification capture and reminders (T002). Owner: w-avisos.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:monekin/core/utils/unique_app_widgets_keys.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
import 'package:monekin/features_ia/inbox/inbox_navigation.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';
import 'package:monekin/features_ia/notifications/notifications_background.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

StreamSubscription<dynamic>? _listenerSub;

/// Channels, plugin, tap handler and, when the user turned them on, the notice reader and the reminders.
/// Never throws: a failure here must not stop the app from starting.
Future<void> initNotificationsFeature() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    final notifier = PluginLocalNotifier.instance;
    await notifier.init(
      onTap: (response) => unawaited(_openPayload(response.payload)),
    );
    final launch = await notifier.plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      unawaited(_openPayload(launch?.notificationResponse?.payload));
    }
    await syncNotificationFeatures();
  } catch (e) {
    debugPrint('Notifications feature not started: $e');
  }
}

/// Applies the saved settings: starts or stops the notice reader and schedules or cancels the reminders.
/// Called at startup and by the settings page after every change.
Future<void> syncNotificationFeatures({NotificationsPrefs? prefs}) async {
  if (kIsWeb || !Platform.isAndroid) return;
  prefs ??= NotificationsPrefs.instance;

  final reading =
      await prefs.listenerEnabled() &&
      await NotificationListenerService.isPermissionGranted();
  if (reading) {
    _listenerSub ??= NotificationListenerService.notificationsStream.listen(
      _onEvent,
    );
    await schedulePeriodicTask(kTaskNoticeScan, const Duration(minutes: 15));
    unawaited(_scanActiveNotices());
  } else {
    await _listenerSub?.cancel();
    _listenerSub = null;
    await cancelBackgroundTask(kTaskNoticeScan);
  }

  if (await prefs.dailyReminderEnabled()) {
    await runDailyReminderTask(prefs: prefs);
    await schedulePeriodicTask(kTaskDailyReminder, const Duration(hours: 24));
  } else {
    await PluginLocalNotifier.instance.cancel(kNotifIdDailyReminder);
    await cancelBackgroundTask(kTaskDailyReminder);
  }

  if (await prefs.budgetAlertsEnabled()) {
    await schedulePeriodicTask(kTaskBudgetCheck, const Duration(hours: 1));
  } else {
    await cancelBackgroundTask(kTaskBudgetCheck);
  }

  if (await prefs.weeklySummaryEnabled()) {
    await schedulePeriodicTask(kTaskWeeklySummary, const Duration(hours: 12));
  } else {
    await cancelBackgroundTask(kTaskWeeklySummary);
  }
}

Future<void> _scanActiveNotices() async {
  try {
    await runNoticeScanTask();
  } catch (e) {
    debugPrint('Notice scan failed: $e');
  }
}

final _processor = NotificationProcessor();

void _onEvent(dynamic event) {
  unawaited(
    handleListenerEvent(
      event,
    ).catchError((Object err) => debugPrint('Notice not processed: $err')),
  );
}

bool _reading = false;
bool _readAgain = false;

/// An event of the plugin is only a trigger. On Android 13 and lower another app can send the same
/// broadcast with any package and text, so nothing in the event is processed: the notices are read back
/// from the active notifications of the listener service bound to this app, which no other app can fill.
/// Events that arrive while a read is running share one more read.
@visibleForTesting
Future<void> handleListenerEvent(
  dynamic event, {
  NotificationProcessor? processor,
  Future<List<dynamic>> Function()? readActive,
}) async {
  final e = event as ServiceNotificationEvent;
  if (e.hasRemoved) return;
  if (_reading) {
    _readAgain = true;
    return;
  }
  _reading = true;
  try {
    do {
      _readAgain = false;
      await processActiveNotices(
        processor: processor ?? _processor,
        readActive: readActive,
      );
    } while (_readAgain);
  } finally {
    _reading = false;
  }
}

/// Opens the review page of the item named by a notification payload (`inbox:<id>`). When the app was
/// just launched the navigator may not exist yet, so it waits for it for a few seconds.
Future<void> _openPayload(String? payload) async {
  if (payload == null || !payload.startsWith(kInboxPayloadPrefix)) return;
  final itemId = payload.substring(kInboxPayloadPrefix.length);
  for (var i = 0; i < 20; i++) {
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      await openInboxReview(context, itemId);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
