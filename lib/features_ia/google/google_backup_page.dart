import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/app/settings/widgets/settings_list_utils.dart';
import 'package:monekin/core/presentation/helpers/snackbar.dart';
import 'package:monekin/core/presentation/widgets/confirm_dialog.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_password_sheets.dart';
import 'package:monekin/features_ia/google/drive_gateway.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';
import 'package:monekin/features_ia/google/restore_flow.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class GoogleBackupPage extends StatefulWidget {
  const GoogleBackupPage({super.key, this.service});

  /// Defaults to the service of the app.
  final DriveBackupService? service;

  @override
  State<GoogleBackupPage> createState() => _GoogleBackupPageState();
}

class _GoogleBackupPageState extends State<GoogleBackupPage> {
  late final service = widget.service ?? DriveBackupService.shared;

  String? email;
  DateTime? lastBackup;
  bool autoBackup = false;
  bool hasPassword = false;
  bool notConfigured = false;
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
        service.hasPassword(),
      ]);
      if (!mounted) return;
      setState(() {
        email = values[0] as String?;
        lastBackup = values[1] as DateTime?;
        autoBackup = values[2] as bool;
        hasPassword = values[3] as bool;
        loading = false;
      });
    } on GoogleNotConfiguredException {
      if (!mounted) return;
      setState(() {
        notConfigured = true;
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
    } on GoogleNotConfiguredException {
      if (mounted) setState(() => notConfigured = true);
    } catch (e) {
      MonekinSnackbar.error(SnackbarParams.fromError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (notConfigured) return;
    await _refresh();
  }

  /// Makes sure a backup password exists, asking for a new one if not. Returns
  /// false when the user dismissed the sheet.
  Future<bool> _ensurePassword() async {
    if (await service.hasPassword()) return true;
    if (!mounted) return false;
    final password = await showCreateBackupPasswordSheet(context);
    if (password == null) return false;
    await service.setPassword(password);
    if (mounted) {
      MonekinSnackbar.success(
        SnackbarParams(Translations.of(context).ia_google.pw_saved),
      );
    }
    return true;
  }

  Future<void> _changePassword() => _run(() async {
    final password = await showCreateBackupPasswordSheet(context, change: true);
    if (password == null) return;
    await service.setPassword(password);
    if (!mounted) return;
    MonekinSnackbar.success(
      SnackbarParams(Translations.of(context).ia_google.pw_saved),
    );
  });

  Future<void> _passwordFirst() => _run(() async {
    await _ensurePassword();
  });

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

  Future<void> _deleteCopies() => _run(() async {
    final t = Translations.of(context).ia_google;
    final confirmed = await confirmDialog(
      context,
      icon: Icons.warning_rounded,
      dialogTitle: t.delete_copies_warn_title,
      contentParagraphs: [Text(t.delete_copies_warn_descr)],
      showCancelButton: true,
    );
    if (confirmed != true) return;

    await service.deleteAllBackups();
    if (!mounted) return;
    MonekinSnackbar.success(SnackbarParams(t.delete_copies_done));
  });

  Future<void> _backupNow() => _run(() async {
    if (!await _ensurePassword()) return;
    await service.backupNow();
    if (!mounted) return;
    MonekinSnackbar.success(
      SnackbarParams(Translations.of(context).ia_google.backup_done),
    );
  });

  Future<void> _setAuto(bool value) => _run(() async {
    if (value) {
      if (!await _ensurePassword()) return;
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

    final bytes = await service.download(picked);
    if (!mounted) return;

    final encrypted = isEncryptedBackup(bytes);
    final confirmed = await confirmDialog(
      context,
      icon: Icons.warning_rounded,
      dialogTitle: encrypted ? t.restore_warn_title : t.restore_plain_title,
      contentParagraphs: [
        Text(
          encrypted
              ? t.restore_warn_descr
              : '${t.restore_plain_descr}\n\n${t.restore_warn_descr}',
        ),
      ],
      showCancelButton: true,
    );
    if (confirmed != true || !mounted) return;

    final restored = await runRestoreAttempts(
      context,
      (password) => service.restoreBytes(bytes, password: password),
    );
    if (!restored || !mounted) return;

    await showRestartRequiredDialog(context);
  });

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
                    if (notConfigured)
                      ..._notConfiguredTiles()
                    else if (email == null)
                      ..._signedOutTiles()
                    else
                      ..._signedInTiles(),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _notConfiguredTiles() {
    final t = Translations.of(context).ia_google;
    return [
      ListTile(
        leading: const Icon(Icons.cloud_off_rounded),
        title: Text(t.google_not_configured),
        subtitle: Text(t.google_not_configured_descr),
      ),
    ];
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
        leading: const Icon(Icons.password_rounded),
        title: Text(hasPassword ? t.pw_change_title : t.pw_create_title),
        subtitle: Text(hasPassword ? t.pw_change_descr : t.pw_encrypted_note),
        enabled: !busy,
        onTap: hasPassword ? _changePassword : _passwordFirst,
      ),
      ListTile(
        leading: const Icon(Icons.delete_outline_rounded),
        title: Text(t.delete_copies),
        subtitle: Text(t.delete_copies_descr),
        enabled: !busy,
        onTap: _deleteCopies,
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
