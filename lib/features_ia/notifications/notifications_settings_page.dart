// Settings of bank-notice reading and reminders (T002). Owner: w-avisos.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/core/presentation/helpers/snackbar.dart';
import 'package:monekin/features_ia/notifications/bank_apps.dart';
import 'package:monekin/features_ia/notifications/local_notifier.dart';
import 'package:monekin/features_ia/notifications/notification_prefs.dart';
import 'package:monekin/features_ia/notifications/notifications_feature.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:permission_handler/permission_handler.dart';

final _packageName = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$');

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key, this.prefs, this.openAppInfo});

  /// Defaults to [NotificationsPrefs.instance].
  final NotificationsPrefs? prefs;

  /// Opens the system page of this app. Defaults to [openAppSettings].
  final Future<bool> Function()? openAppInfo;

  @override
  State<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage>
    with WidgetsBindingObserver {
  late final NotificationsPrefs _prefs =
      widget.prefs ?? NotificationsPrefs.instance;
  late final Future<bool> Function() _openAppInfo =
      widget.openAppInfo ?? openAppSettings;

  bool _loaded = false;
  bool _unreadable = false;
  bool _reading = false;
  bool _accessGranted = false;
  // The user asked to read notices and the access is still missing. The activation
  // finishes by itself once the access is granted.
  bool _pendingAccess = false;
  Set<String> _watched = {};
  bool _daily = false;
  int _dailyMinutes = 20 * 60;
  bool _budget = true;
  bool _weekly = false;
  bool _aiNotices = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_onResumed());
  }

  /// Back from the system access screen: completes a pending activation, then reloads.
  Future<void> _onResumed() async {
    if (_pendingAccess &&
        await NotificationListenerService.isPermissionGranted()) {
      _pendingAccess = false;
      await _prefs.setListenerEnabled(true);
      await _apply();
    }
    await _load();
  }

  Future<void> _load() async {
    final granted = await NotificationListenerService.isPermissionGranted();
    final bool reading, daily, budget, weekly, aiNotices;
    final Set<String> watched;
    final int minutes;
    try {
      reading = await _prefs.listenerEnabled();
      watched = await _prefs.watchedPackages();
      daily = await _prefs.dailyReminderEnabled();
      minutes = await _prefs.dailyReminderMinutes();
      budget = await _prefs.budgetAlertsEnabled();
      weekly = await _prefs.weeklySummaryEnabled();
      aiNotices = await _prefs.aiNoticesEnabled();
    } on StoreCorruptedException {
      if (!mounted) return;
      setState(() {
        _unreadable = true;
        _loaded = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _unreadable = false;
      _accessGranted = granted;
      _reading = reading && granted;
      _watched = watched;
      _daily = daily;
      _dailyMinutes = minutes;
      _budget = budget;
      _weekly = weekly;
      _aiNotices = aiNotices;
      _loaded = true;
    });
  }

  Future<void> _apply() => syncNotificationFeatures(prefs: _prefs);

  Future<void> _reset() async {
    final tr = Translations.of(context).ia_notifications;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.reset_settings),
        content: Text(tr.reset_confirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const ValueKey('notifications-reset-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr.reset_settings),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _prefs.reset();
    await _load();
    await _apply();
  }

  void _error(String message) => MonekinSnackbar.error(SnackbarParams(message));

  Future<void> _setReading(bool on) async {
    final tr = Translations.of(context).ia_notifications;
    if (!on) {
      await _prefs.setListenerEnabled(false);
      setState(() => _reading = false);
      return _apply();
    }
    // The system dialog for posting notifications comes first; the access list is a settings screen.
    final canPost = await PluginLocalNotifier.instance.requestPermission();
    if (!canPost) _error(tr.post_permission_denied);
    var granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      granted = await NotificationListenerService.requestPermission();
    }
    if (!mounted) return;
    setState(() {
      _accessGranted = granted;
      _pendingAccess = !granted;
    });
    if (!granted) return _error(tr.permission_denied);
    await _prefs.setListenerEnabled(true);
    setState(() => _reading = true);
    await _apply();
  }

  Future<void> _setWatched(String package, bool on) async {
    final next = {..._watched};
    on ? next.add(package) : next.remove(package);
    await _prefs.setWatchedPackages(next);
    setState(() => _watched = next);
  }

  Future<void> _addApp() async {
    final tr = Translations.of(context).ia_notifications;
    final controller = TextEditingController();
    final package = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.add_app),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          decoration: InputDecoration(hintText: tr.add_app_hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (package == null || package.isEmpty) return;
    if (!_packageName.hasMatch(package)) return _error(tr.add_app_invalid);
    await _setWatched(package, true);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _dailyMinutes ~/ 60,
        minute: _dailyMinutes % 60,
      ),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await _prefs.setDailyReminderMinutes(minutes);
    setState(() => _dailyMinutes = minutes);
    await _apply();
  }

  Future<void> _toggle(
    Future<void> Function(bool) save,
    bool on,
    void Function(bool) assign,
  ) async {
    if (on) await PluginLocalNotifier.instance.requestPermission();
    await save(on);
    setState(() => assign(on));
    await _apply();
  }

  @override
  Widget build(BuildContext context) {
    final tr = Translations.of(context).ia_notifications;
    final theme = Theme.of(context);
    final customPackages = _watched.where((p) => bankAppFor(p) == null).toList()
      ..sort();

    return PageFramework(
      title: tr.title,
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _unreadable
          ? ListView(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(tr.settings_unreadable),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton(
                      key: const ValueKey('notifications-reset'),
                      onPressed: _reset,
                      child: Text(tr.reset_settings),
                    ),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                SwitchListTile(
                  title: Text(tr.reader_title),
                  subtitle: Text(tr.reader_descr),
                  value: _reading,
                  onChanged: _setReading,
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(tr.privacy_title),
                  subtitle: Text(tr.privacy_body),
                ),
                SwitchListTile(
                  title: Text(tr.ai_notices_title),
                  subtitle: Text(tr.ai_notices_descr),
                  value: _aiNotices,
                  onChanged: (v) async {
                    await _prefs.setAiNoticesEnabled(v);
                    setState(() => _aiNotices = v);
                  },
                ),
                if (_pendingAccess)
                  _AccessHelpCard(
                    onOpenAppInfo: _openAppInfo,
                    onRetry: () => _setReading(true),
                  )
                else if (!_accessGranted)
                  ListTile(
                    leading: Icon(
                      Icons.lock_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(tr.permission_needed),
                    trailing: FilledButton(
                      onPressed: () => _setReading(true),
                      child: Text(tr.permission_button),
                    ),
                  ),
                const Divider(),
                ListTile(
                  title: Text(
                    tr.watched_apps,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                for (final app in kKnownBankApps)
                  CheckboxListTile(
                    title: Text(app.name),
                    subtitle: Text(app.package),
                    value: _watched.contains(app.package),
                    onChanged: (v) => _setWatched(app.package, v ?? false),
                  ),
                for (final package in customPackages)
                  CheckboxListTile(
                    title: Text(package),
                    value: true,
                    onChanged: (v) => _setWatched(package, v ?? false),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(tr.add_app),
                  onTap: _addApp,
                ),
                const Divider(),
                ListTile(
                  title: Text(
                    tr.reminders_title,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                SwitchListTile(
                  title: Text(tr.daily_reminder),
                  value: _daily,
                  onChanged: (v) => _toggle(
                    _prefs.setDailyReminderEnabled,
                    v,
                    (x) => _daily = x,
                  ),
                ),
                if (_daily)
                  ListTile(
                    title: Text(tr.daily_reminder_time),
                    trailing: Text(
                      TimeOfDay(
                        hour: _dailyMinutes ~/ 60,
                        minute: _dailyMinutes % 60,
                      ).format(context),
                      style: theme.textTheme.titleMedium,
                    ),
                    onTap: _pickTime,
                  ),
                SwitchListTile(
                  title: Text(tr.budget_alerts),
                  subtitle: Text(tr.budget_alerts_descr),
                  value: _budget,
                  onChanged: (v) => _toggle(
                    _prefs.setBudgetAlertsEnabled,
                    v,
                    (x) => _budget = x,
                  ),
                ),
                SwitchListTile(
                  title: Text(tr.weekly_summary),
                  subtitle: Text(tr.weekly_summary_descr),
                  value: _weekly,
                  onChanged: (v) => _toggle(
                    _prefs.setWeeklySummaryEnabled,
                    v,
                    (x) => _weekly = x,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Shown while the notification access is missing after a request: how to grant it on phones
/// that block the switch with «Ajuste restringido».
class _AccessHelpCard extends StatelessWidget {
  const _AccessHelpCard({required this.onOpenAppInfo, required this.onRetry});

  final VoidCallback onOpenAppInfo;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tr = Translations.of(context).ia_notifications;
    final theme = Theme.of(context);
    final steps = [
      tr.access_help_step1,
      tr.access_help_step2,
      tr.access_help_step3,
    ];

    return Card(
      key: const ValueKey('notifications-access-help'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.access_help_title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final (i, step) in steps.indexed) Text('${i + 1}. $step'),
            const SizedBox(height: 8),
            Text(tr.access_help_note, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const ValueKey('notifications-access-app-info'),
                  onPressed: onOpenAppInfo,
                  child: Text(tr.open_app_info),
                ),
                FilledButton(
                  key: const ValueKey('notifications-access-retry'),
                  onPressed: onRetry,
                  child: Text(tr.permission_button),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
