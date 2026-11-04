// Card map: last four digits -> Monekin account id (T002). Owner: w-utils.
// Stored in a JSON file in the app documents dir; it never holds full card numbers.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

final _last4 = RegExp(r'^\d{4}$');

class CardMapService {
  CardMapService._();

  static final CardMapService instance = CardMapService._();

  /// Test seam: replaces the app documents directory.
  @visibleForTesting
  Future<Directory> Function()? debugDirectory;

  Future<Map<String, String>> load() async {
    final file = await _file();

    if (!await file.exists()) return {};

    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    return {
      for (final entry in decoded.entries) entry.key: entry.value as String,
    };
  }

  Future<void> save(Map<String, String> last4ToAccountId) async {
    for (final last4 in last4ToAccountId.keys) {
      if (!_last4.hasMatch(last4)) {
        throw ArgumentError.value(last4, 'last4', 'must be exactly 4 digits');
      }
    }

    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(last4ToAccountId));
  }

  /// Account id for a card ending in [last4], or null.
  Future<String?> accountFor(String last4) async => (await load())[last4];

  Future<File> _file() async {
    final documents =
        await (debugDirectory?.call() ?? getApplicationDocumentsDirectory());

    return File('${documents.path}/finanzas_ia/card_map.json');
  }
}
