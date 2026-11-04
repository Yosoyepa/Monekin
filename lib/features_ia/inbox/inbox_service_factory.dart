// Factory of the real inbox service (T002). Owner: w-inbox.
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/features_ia/inbox/drift_inbox_service.dart';

DriftInboxService createInboxService() => DriftInboxService(
  db: AppDB.instance,
  transactions: TransactionService.instance,
);
