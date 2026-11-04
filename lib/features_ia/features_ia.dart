// Startup of the AI features of the Finanzas IA fork (T002). Owner: architect.
// Each feature owns its folder under lib/features_ia; this file only wires them.
import 'package:flutter/foundation.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/pre_restore_copies.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_factory.dart';
import 'package:monekin/features_ia/core/background/background_tasks.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';
import 'package:monekin/features_ia/google/google_backup_service_factory.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/inbox/inbox_service_factory.dart';
import 'package:monekin/features_ia/insights/insights_service.dart';
import 'package:monekin/features_ia/insights/insights_service_factory.dart';
import 'package:monekin/features_ia/notifications/notifications_feature.dart';

/// Never throws: an optional feature that fails to start (a plugin, the notification listener) must not
/// keep Monekin from opening. The failure is logged and that feature stays off until the next start.
/// [deletePreCopies] and [purgeInbox] default to the real startup cleanup; tests pass their own.
Future<void> initFeaturesIa({
  Future<void> Function()? deletePreCopies,
  Future<void> Function()? purgeInbox,
}) async {
  final inbox = createInboxService();
  AiService.instance = createAiService();
  InboxService.instance = inbox;
  InsightsService.instance = createInsightsService();
  GoogleBackupService.instance = createGoogleBackupService();
  await _guard('background tasks', initBackgroundTasks);
  await _guard('notifications', initNotificationsFeature);
  await _guard('pre-restore copies', deletePreCopies ?? _deletePreCopies);
  await _guard(
    'inbox purge',
    purgeInbox ??
        () async {
          await inbox.purgeOld(now: DateTime.now());
        },
  );
}

/// Deletes the copies kept before the last restore or import, once the database is
/// proven healthy and they have waited long enough (see [cleanPreCopies]).
Future<void> _deletePreCopies() async {
  final db = AppDB.instance;
  await cleanPreCopies(
    dbPath: await db.databasePath,
    state: PreCopiesState.inSupportDir(),
    now: DateTime.now(),
    check: () => checkDatabaseHealth(
      (sql) async => [
        for (final row in await db.customSelect(sql).get()) row.data,
      ],
      userVersion: db.schemaVersion,
      requiredTables: db.allTables.map((table) => table.actualTableName),
    ),
  );
}

/// Only the feature and the kind of error are logged: the message of a database or
/// file error can carry the user's data.
Future<void> _guard(String feature, Future<void> Function() init) async {
  try {
    await init();
  } catch (e) {
    debugPrint('Finanzas IA: $feature failed (${e.runtimeType})');
  }
}
