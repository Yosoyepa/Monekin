// Shared steps of restoring an encrypted or packaged backup (T002, round 3), used by
// the Drive page and by the local restore.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monekin/core/presentation/helpers/snackbar.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_password_sheets.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// Runs [attempt] until it restores, asking for the password whenever the copy needs
/// one (again after a wrong one). Returns false when nothing was restored (dismissed
/// or failed); the data is untouched in that case.
Future<bool> runRestoreAttempts(
  BuildContext context,
  Future<void> Function(String? password) attempt,
) async {
  String? password;

  while (true) {
    try {
      await attempt(password);
      return true;
    } on InvalidBackupException catch (e) {
      final needsPassword =
          e.reason == InvalidBackupReason.passwordRequired ||
          e.reason == InvalidBackupReason.wrongPassword;
      if (!context.mounted) return false;

      if (!needsPassword) {
        final t = Translations.of(context).ia_google;
        MonekinSnackbar.error(
          SnackbarParams(switch (e.reason) {
            InvalidBackupReason.newerSchema => t.restore_newer,
            InvalidBackupReason.tampered => t.restore_tampered,
            _ => t.restore_invalid,
          }),
        );
        return false;
      }

      password = await showRestorePasswordSheet(
        context,
        wrongBefore: e.reason == InvalidBackupReason.wrongPassword,
      );
      if (password == null) return false;
    } on RestoreNeedsRestartException {
      if (context.mounted) {
        await showRestartRequiredPage(context, failed: true);
      }
      return false;
    }
  }
}

Future<void> _closeApp() async {
  if (Platform.isAndroid) {
    await SystemNavigator.pop();
  } else {
    exit(0);
  }
}

/// The old database connection is closed: the app has to start again, on the restored
/// database or, when the restore [failed] after the close, on the data it had.
///
/// It replaces every route with [RestartRequiredPage], so no screen that reads the closed
/// database is left alive underneath to rebuild and fail.
Future<void> showRestartRequiredPage(
  BuildContext context, {
  bool failed = false,
}) {
  return Navigator.of(context, rootNavigator: true).pushAndRemoveUntil<void>(
    MaterialPageRoute(builder: (_) => RestartRequiredPage(failed: failed)),
    (_) => false,
  );
}

/// The last screen after a restore: it reads nothing from the database.
class RestartRequiredPage extends StatelessWidget {
  const RestartRequiredPage({
    super.key,
    this.failed = false,
    this.closeApp = _closeApp,
  });

  final bool failed;
  final Future<void> Function() closeApp;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_google;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.restart_alt_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      failed ? t.restore_failed_title : t.restore_done,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      failed ? t.restore_failed_descr : t.restore_restart_descr,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: closeApp,
                      child: Text(t.restore_restart_button),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
