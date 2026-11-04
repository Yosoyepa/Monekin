import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/backup/backup_database_service.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configuration files never contain the saved key', () async {
    final directory = await Directory.systemTemp.createTemp('ai-private-');
    addTearDown(() async => directory.delete(recursive: true));
    FlutterSecureStorage.setMockInitialValues({});
    final service = AiServiceImpl(
      configFile: () async => File('${directory.path}/ai_settings.json'),
    );
    const secret = 'sentinel-only-for-secure-storage';
    final dbFile = File('${directory.path}/database.db');
    final db = _TestDatabase(dbFile);
    final backup = BackupDatabaseService()..db = db;
    final logs = <String>[];
    await runZoned(
      () async {
        await db.customSelect('SELECT 1').get();
        await service.saveConfig(aiPresets[AiProviderId.gemini]!);
        await service.saveKey(secret);
        await db.close();
        await backup.exportDatabaseFile(directory.path);
        await backup.exportSpreadsheet(directory.path, []);
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => logs.add(line),
      ),
    );
    expect(await service.isConfigured(), isTrue);
    final keyName = AiServiceImpl.keyNameFor(aiPresets[AiProviderId.gemini]!);
    expect(await const FlutterSecureStorage().read(key: keyName), secret);
    final files = await directory
        .list(recursive: true)
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    expect(files.where((file) => file.path.endsWith('.db')), hasLength(2));
    expect(files.where((file) => file.path.endsWith('.csv')), hasLength(1));
    for (final file in files) {
      expect(latin1.decode(await file.readAsBytes()), isNot(contains(secret)));
    }
    expect(logs.join('\n'), isNot(contains(secret)));
    await service.deleteKey();
    expect(await const FlutterSecureStorage().read(key: keyName), isNull);
  });
}

class _TestDatabase extends AppDB {
  _TestDatabase(this.file) : super.forTesting(NativeDatabase(file));
  final File file;

  @override
  Future<String> get databasePath async => file.path;
}
