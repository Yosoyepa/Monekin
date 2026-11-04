// Small local state of the Drive backup (last copy date, daily copy switch). T002.
// A JSON file instead of the app database: the background isolate reads it too.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

abstract class BackupStateStore {
  Future<DateTime?> lastBackup();

  Future<void> setLastBackup(DateTime value);

  Future<bool> autoEnabled();

  Future<void> setAutoEnabled(bool value);
}

class FileBackupStateStore implements BackupStateStore {
  FileBackupStateStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async =>
      File(path.join((await _directory()).path, 'finanzas_drive_backup.json'));

  Future<Map<String, dynamic>> _read() async {
    final file = await _file();
    if (!file.existsSync()) return {};
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final file = await _file();
    await file.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  }

  @override
  Future<DateTime?> lastBackup() async {
    final raw = (await _read())['lastBackup'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  @override
  Future<void> setLastBackup(DateTime value) async {
    final data = await _read();
    data['lastBackup'] = value.toIso8601String();
    await _write(data);
  }

  @override
  Future<bool> autoEnabled() async => (await _read())['auto'] == true;

  @override
  Future<void> setAutoEnabled(bool value) async {
    final data = await _read();
    data['auto'] = value;
    await _write(data);
  }
}

class MemoryBackupStateStore implements BackupStateStore {
  DateTime? _last;
  bool _auto = false;

  @override
  Future<DateTime?> lastBackup() async => _last;

  @override
  Future<void> setLastBackup(DateTime value) async => _last = value;

  @override
  Future<bool> autoEnabled() async => _auto;

  @override
  Future<void> setAutoEnabled(bool value) async => _auto = value;
}
