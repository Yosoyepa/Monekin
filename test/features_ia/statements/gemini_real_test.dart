import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';

class _Catalog extends AiCatalog {
  const _Catalog() : super(accounts: const [], categories: const []);
  @override
  String toPromptJson() => '{"accounts":[],"categories":[]}';
}

class _Gemini implements AiClient {
  _Gemini(this.key);
  final String key;
  @override
  Future<AiResult> chat(
    List<AiMessage> messages, {
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final response = await http
        .post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
          ),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'gemini-flash-lite-latest',
            'messages': [
              for (final message in messages)
                {'role': message.role, 'content': message.text},
            ],
            'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw StateError('Gemini HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>;
    return AiResult(text: (choices.first['message']['content'] as String));
  }

  @override
  Future<List<String>> listModels() async => [];
}

double? _amount(String raw) {
  var value = raw.replaceAll(RegExp(r'[^0-9,.+\-]'), '');
  if (value.contains(',')) {
    if (value.lastIndexOf(',') > value.lastIndexOf('.')) {
      value = value.replaceAll('.', '').replaceAll(',', '.');
    } else {
      value = value.replaceAll(',', '');
    }
  } else if (RegExp(r'^[-+]?\d{1,3}(\.\d{3})+$').hasMatch(value)) {
    value = value.replaceAll('.', '');
  }
  return double.tryParse(value);
}

void main() {
  final keyFile = File('D:/Dev/secrets/gemini_test_key.txt');
  final hasKey =
      (Platform.environment['GEMINI_TEST_API_KEY']?.trim().isNotEmpty ??
          false) ||
      keyFile.existsSync();
  test(
    'real Gemini reconciles extracted PDF',
    () async {
      final key =
          Platform.environment['GEMINI_TEST_API_KEY']?.trim() ??
          (await keyFile.readAsString()).trim();
      final text = await File(
        'test/features_ia/statements/bancolombia_extracted.txt',
      ).readAsString();
      final importer = StatementImporter(
        amountParser: _amount,
        catalogLoader: () async => const _Catalog(),
        clientLoader: () async => _Gemini(key),
      );
      final result = await importer.parseWithAi(text, 'account');
      expect(result.rows.length, 12);
      expect(result.net, 3162650);
      expect(result.difference, 0);
    },
    skip: hasKey ? false : 'No Gemini test key',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
