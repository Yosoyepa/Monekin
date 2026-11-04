import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/app/settings/widgets/settings_list_utils.dart';
import 'package:monekin/core/presentation/helpers/snackbar.dart';
import 'package:monekin/core/presentation/widgets/confirm_dialog.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/drive_gateway.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class GoogleBackupPage extends StatefulWidget {
  const GoogleBackupPage({super.key});

  @override
  State<GoogleBackupPage> createState() => _GoogleBackupPageState();
}

class _GoogleBackupPageState extends State<GoogleBackupPage> {
  final service = DriveBackupService.shared;

  String? email;
  DateTime? lastBackup;
  bool autoBackup = false;
  bool loading = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final values = await Future.wait([
        service.signedInEmail(),
        service.lastBackup(),
        service.autoEnabled(),
      ]);
      if (!mounted) return;
      setState(() {
        email = values[0] as String?;
        lastBackup = values[1] as DateTime?;
        autoBackup = values[2] as bool;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      MonekinSnackbar.error(SnackbarParams.fromError(e));
    }
  }

  /// Runs [action] disabling the buttons meanwhile and reporting errors.
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } on NotSignedInException {
      if (mounted) {
        MonekinSnackbar.error(
          SnackbarParams(Translations.of(context).ia_google.not_signed_in),
        );
      }
    } catch (e) {
      MonekinSnackbar.error(SnackbarParams.fromError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await _refresh();
  }

  Future<void> _signIn() => _run(() async {
    final account = await service.signIn();
    if (account != null && mounted) {
      MonekinSnackbar.success(
        SnackbarParams(Translations.of(context).ia_google.signed_in),
      );
    }
  });

  Future<void> _signOut() => _run(() async {
    await cancelBackgroundTask(kTaskDriveBackup);
    await service.signOut();
  });

  Future<void> _backupNow() => _run(() async {
    await service.backupNow();
    if (!mounted) return;
    MonekinSnackbar.success(
      SnackbarParams(Translations.of(context).ia_google.backup_done),
    );
  });

  Future<void> _setAuto(bool value) => _run(() async {
    if (value) {
      await schedulePeriodicTask(kTaskDriveBackup, const Duration(days: 1));
    } else {
      await cancelBackgroundTask(kTaskDriveBackup);
    }
    await service.setAutoEnabled(value);
  });

  Future<void> _restore() => _run(() async {
    final t = Translations.of(context).ia_google;
    final files = await service.listBackups();
    if (!mounted) return;
    if (files.isEmpty) {
      MonekinSnackbar.info(SnackbarParams(t.restore_none));
      return;
    }

    final picked = await showDialog<DriveBackupFile>(
      context: context,
      builder: (context) => _BackupPickerDialog(files: files),
    );
    if (picked == null || !mounted) return;

    final confirmed = await confirmDialog(
      context,
      icon: Icons.warning_rounded,
      dialogTitle: t.restore_warn_title,
      contentParagraphs: [Text(t.restore_warn_descr)],
      showCancelButton: true,
    );
    if (confirmed != true) return;

    try {
      await service.restore(picked);
    } on InvalidBackupException catch (e) {
      MonekinSnackbar.error(
        SnackbarParams(
          e.reason == InvalidBackupReason.newerSchema
              ? t.restore_newer
              : t.restore_invalid,
        ),
      );
      return;
    }
    if (!mounted) return;

    // The old connection is closed: the app has to start again on the restored database.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.restart_alt_rounded),
          title: Text(t.restore_done),
          content: Text(t.restore_restart_descr),
          actions: [
            FilledButton(
              onPressed: _closeApp,
              child: Text(t.restore_restart_button),
            ),
          ],
        ),
      ),
    );
  });

  Future<void> _closeApp() async {
    if (Platform.isAndroid) {
      await SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_google;

    return PageFramework(
      title: t.title,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: ListTileTheme(
                data: getSettingListTileStyle(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(t.descr),
                    ),
                    if (email == null)
                      ..._signedOutTiles()
                    else
                      ..._signedInTiles(),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _signedOutTiles() {
    final t = Translations.of(context).ia_google;
    return [
      ListTile(
        leading: const Icon(Icons.login_rounded),
        title: Text(t.sign_in),
        subtitle: Text(t.optional_note),
        enabled: !busy,
        onTap: _signIn,
      ),
    ];
  }

  List<Widget> _signedInTiles() {
    final t = Translations.of(context).ia_google;
    return [
      ListTile(
        leading: const Icon(Icons.account_circle_rounded),
        title: Text(t.connected_as(email: email!)),
        subtitle: Text(
          lastBackup == null
              ? t.last_backup_never
              : t.last_backup(date: _format(lastBackup!)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.cloud_upload_rounded),
        title: Text(t.backup_now),
        enabled: !busy,
        onTap: _backupNow,
      ),
      ListTile(
        leading: const Icon(Icons.cloud_download_rounded),
        title: Text(t.restore),
        subtitle: Text(t.restore_descr),
        enabled: !busy,
        onTap: _restore,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.schedule_rounded),
        title: Text(t.auto_title),
        subtitle: Text(t.auto_descr),
        value: autoBackup,
        onChanged: busy ? null : _setAuto,
      ),
      ListTile(
        leading: const Icon(Icons.logout_rounded),
        title: Text(t.sign_out),
        enabled: !busy,
        onTap: _signOut,
      ),
    ];
  }

  String _format(DateTime date) => DateFormat.yMd(
    Localizations.localeOf(context).toString(),
  ).add_Hm().format(date);
}

class _BackupPickerDialog extends StatelessWidget {
  const _BackupPickerDialog({required this.files});

  final List<DriveBackupFile> files;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final format = DateFormat.yMd(locale).add_Hm();

    return SimpleDialog(
      title: Text(Translations.of(context).ia_google.restore_pick_title),
      children: [
        for (final file in files)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(file),
            child: Text(format.format(file.created.toLocal())),
          ),
      ],
    );
  }
}
