// Local notifications of Finanzas IA (T002). Owner: w-avisos.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum AlertChannel { detected, reminders, budget, weekly }

const kNotifIdDailyReminder = 9001;
const kNotifIdWeeklySummary = 9002;

/// Title of the notifications whose text must say nothing about the user's money.
const kGenericNotificationTitle = 'Finanzas IA';

/// Payload of the «new expense detected» notification: the inbox item to open.
const kInboxPayloadPrefix = 'inbox:';

abstract class LocalNotifier {
  Future<void> show({
    required int id,
    required AlertChannel channel,
    required String title,
    required String body,
    String? payload,
  });
}

/// Positive notification id derived from a string (item or budget id).
int notificationIdFor(String key) => key.hashCode & 0x7fffffff;

class PluginLocalNotifier implements LocalNotifier {
  PluginLocalNotifier._();

  static final PluginLocalNotifier instance = PluginLocalNotifier._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Sets up the plugin and the channels. Safe to call again (also from a background isolate).
  Future<void> init({DidReceiveNotificationResponseCallback? onTap}) async {
    if (_ready) return;
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: onTap,
    );
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final tr = t.ia_notifications;
    for (final (channel, name) in [
      (AlertChannel.detected, tr.channel_detected),
      (AlertChannel.reminders, tr.channel_reminders),
      (AlertChannel.budget, tr.channel_budget),
      (AlertChannel.weekly, tr.channel_weekly),
    ]) {
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId(channel),
          name,
          importance: Importance.high,
        ),
      );
    }
    _ready = true;
  }

  static String _channelId(AlertChannel c) => 'finanzas_${c.name}';

  NotificationDetails _details(AlertChannel c, {String? name}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId(c),
          name ?? c.name,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: const BigTextStyleInformation(''),
        ),
      );

  /// Asks for the POST_NOTIFICATIONS permission (Android 13+). True when notifications can be shown.
  Future<bool> requestPermission() async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> show({
    required int id,
    required AlertChannel channel,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    await plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId(channel),
          channel.name,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: payload,
    );
  }

  Future<void> _initTimezone() async {
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(
        tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
      );
    } catch (e) {
      debugPrint('Timezone not found, using UTC: $e');
    }
  }

  /// Next [hour]:[minute] in the device time zone, strictly after [from].
  @visibleForTesting
  static tz.TZDateTime nextOccurrence(
    tz.Location location,
    int hour,
    int minute,
    tz.TZDateTime from,
  ) {
    var at = tz.TZDateTime(
      location,
      from.year,
      from.month,
      from.day,
      hour,
      minute,
    );
    if (!at.isAfter(from)) at = at.add(const Duration(days: 1));
    return at;
  }

  /// Repeats every day at [hour]:[minute]. Replaces the previous one (same id).
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await init();
    await _initTimezone();
    final first = nextOccurrence(
      tz.local,
      hour,
      minute,
      tz.TZDateTime.now(tz.local),
    );
    await plugin.zonedSchedule(
      id: kNotifIdDailyReminder,
      title: title,
      body: body,
      scheduledDate: first,
      notificationDetails: _details(AlertChannel.reminders),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel(int id) async {
    await init();
    await plugin.cancel(id: id);
  }
}
