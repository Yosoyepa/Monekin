// Startup of the AI features of the Finanzas IA fork (T002). Owner: architect.
// Each feature owns its folder under lib/features_ia; this file only wires them.
import 'package:flutter/foundation.dart';
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
Future<void> initFeaturesIa() async {
  AiService.instance = createAiService();
  InboxService.instance = createInboxService();
  InsightsService.instance = createInsightsService();
  GoogleBackupService.instance = createGoogleBackupService();
  await _guard('background tasks', initBackgroundTasks);
  await _guard('notifications', initNotificationsFeature);
}

Future<void> _guard(String feature, Future<void> Function() init) async {
  try {
    await init();
  } catch (e, st) {
    debugPrint('Finanzas IA: $feature not started: $e\n$st');
  }
}
