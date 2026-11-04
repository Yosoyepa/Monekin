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

/// The old database connection is closed: the app has to start again on the
/// restored database.
Future<void> showRestartRequiredDialog(BuildContext context) {
  final t = Translations.of(context).ia_google;

  return showDialog<void>(
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
}
