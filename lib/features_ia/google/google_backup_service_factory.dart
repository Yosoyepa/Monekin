// Factory of the real Google backup service (T002). Owner: w-google.
import 'package:monekin/features_ia/google/google_backup_service.dart';

GoogleBackupService createGoogleBackupService() => DriveBackupService.shared;
