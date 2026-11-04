import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/app/settings/pages/backup/export_page.dart';
import 'package:monekin/app/settings/pages/backup/import_csv.page.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/backup_database_service.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:monekin/core/extensions/numbers.extensions.dart';
import 'package:monekin/core/presentation/helpers/snackbar.dart';
import 'package:monekin/core/presentation/widgets/confirm_dialog.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../../widgets/settings_list_utils.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/restore_flow.dart';
import 'package:monekin/features_ia/google/google_backup_page.dart';

class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  /// Whether the copy kept before the last restore could not be cleaned up.
  late final Future<bool> _preCopiesWarning = PreCopiesState.inSupportDir()
      .hasWarning()
      .catchError((_) => false);

  /// Restores a file picked by the user, whatever its version: an encrypted copy, a
  /// package or a bare database. All go through the same two phases (the app restarts
  /// afterwards), and one that is not encrypted needs an explicit yes first.
  Future<void> _importBackup() async {
    final t = Translations.of(context);
    final service = BackupDatabaseService();

    try {
      final bytes = await service.pickBackupBytes();

      if (bytes == null) {
        RouteUtils.popRoute();

        MonekinSnackbar.info(SnackbarParams(t.backup.no_file_selected));

        return;
      }

      if (!mounted) return;

      if (!isEncryptedBackup(bytes)) {
        final accepted = await confirmDialog(
          context,
          icon: Icons.warning_rounded,
          dialogTitle: t.ia_google.restore_plain_title,
          contentParagraphs: [Text(t.ia_google.restore_plain_descr)],
          showCancelButton: true,
        );
        if (accepted != true || !mounted) return;
      }

      final restored = await runRestoreAttempts(
        context,
        (password) => service.restorePackage(
          bytes,
          password: password,
          unencryptedConfirmed: true,
        ),
      );
      if (!restored || !mounted) return;

      await showRestartRequiredDialog(context);
    } catch (err) {
      RouteUtils.popRoute();

      MonekinSnackbar.error(SnackbarParams.fromError(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PageFramework(
      title: t.more.data.display,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 0),
        child: ListTileTheme(
          data: getSettingListTileStyle(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<bool>(
                future: _preCopiesWarning,
                builder: (context, snapshot) => snapshot.data == true
                    ? ListTile(
                        leading: const Icon(Icons.warning_amber_rounded),
                        title: Text(t.ia_google.pre_copies_warning),
                        minVerticalPadding: 16,
                      )
                    : const SizedBox.shrink(),
              ),
              createListSeparator(context, t.backup.import.title),
              ListTile(
                title: Text(t.backup.import.restore_backup),
                subtitle: Text(t.backup.import.restore_backup_descr),
                minVerticalPadding: 16,
                onTap: () {
                  confirmDialog(
                    context,
                    icon: Icons.warning_rounded,
                    dialogTitle: t.backup.import.restore_backup_warn_title,
                    contentParagraphs: [
                      Text(t.backup.import.restore_backup_warn_description),
                    ],
                  ).then((value) {
                    if (value == null || !value) {
                      return;
                    }

                    unawaited(_importBackup());
                  });
                },
              ),
              ListTile(
                title: Text(t.backup.import.manual_import.title),
                subtitle: Text(t.backup.import.manual_import.descr),
                minVerticalPadding: 16,
                onTap: () {
                  RouteUtils.pushRoute(const ImportCSVPage());
                },
              ),
              createListSeparator(context, t.backup.export.title_short),
              ListTile(
                title: Text(t.backup.export.title),
                subtitle: Text(t.backup.export.description),
                minVerticalPadding: 16,
                onTap: () {
                  RouteUtils.pushRoute(const ExportDataPage());
                },
              ),
              ListTile(
                title: Text(t.ia_google.title),
                subtitle: Text(t.ia_google.descr),
                minVerticalPadding: 16,
                onTap: () {
                  RouteUtils.pushRoute(const GoogleBackupPage());
                },
              ),
              createListSeparator(context, t.backup.about.title),
              ListTile(
                title: Text(t.backup.about.modify_date),
                trailing: FutureBuilder(
                  future: AppDB.instance.databasePath,
                  builder: (context, snapshot) {
                    final path = snapshot.data;

                    if (path == null || path.isEmpty) {
                      return const Text('----');
                    }

                    return Text(
                      DateFormat.yMMMd().add_Hm().format(
                        File(path).lastModifiedSync(),
                      ),
                    );
                  },
                ),
              ),
              ListTile(
                title: Text(t.backup.about.size),
                trailing: FutureBuilder(
                  future: AppDB.instance.getDatabaseFile().then(
                    (value) => value.stat(),
                  ),
                  builder: (context, snapshot) {
                    final fileStats = snapshot.data;

                    if (fileStats == null) {
                      return const Text('----');
                    }

                    return Text(fileStats.size.readableFileSize());
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
