import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:pdfrx/pdfrx.dart';

typedef AmountParser = double? Function(String);

/// Rows sent per call when the AI proposes categories.
const _categoryBatch = 60;

class StatementResult {
  StatementResult(
    this.rows,
    this.initialBalance,
    this.finalBalance, {
    this.categoryWarning = false,
  });
  final List<ProposedTransaction> rows;
  final double? initialBalance;
  final double? finalBalance;

  /// True when the AI could not propose categories, so some rows keep none.
  final bool categoryWarning;
  double get net => rows.fold(
    0,
    (sum, row) =>
        sum + (row.type == TransactionType.income ? row.amount : -row.amount),
  );
  double? get difference => initialBalance == null || finalBalance == null
      ? null
      : net - (finalBalance! - initialBalance!);
}

class StatementImporter {
  StatementImporter({
    this.amountParser = parseLocalizedAmount,
    this.catalogLoader = loadAiCatalog,
    this.clientLoader,
    this.inbox,
  });
  final AmountParser amountParser;
  final Future<AiCatalog> Function() catalogLoader;
  final Future<AiClient> Function()? clientLoader;
  final InboxService? inbox;

  String decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes).replaceFirst('\uFEFF', '');
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  Future<String> extractPdf(Uint8List bytes) async {
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openData(bytes);
    try {
      final pages = <String>[];
      for (final page in document.pages) {
        pages.add((await page.loadText())?.fullText ?? '');
      }
      return pages.join('\n');
    } finally {
      await document.dispose();
    }
  }

  String _normalize(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp('[áàä]'), 'a')
      .replaceAll(RegExp('[éèë]'), 'e')
      .replaceAll(RegExp('[íìï]'), 'i')
      .replaceAll(RegExp('[óòö]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u');

  DateTime? _date(String value) {
    final match = RegExp(
      r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})$',
    ).firstMatch(value.trim());
    if (match != null) {
      final d = int.parse(match[1]!);
      final m = int.parse(match[2]!);
      final y = int.parse(match[3]!);
      final date = DateTime(y, m, d);
      return date.year == y && date.month == m && date.day == d ? date : null;
    }
    return DateTime.tryParse(value.trim());
  }

  StatementResult? parseCsv(String text, String accountId) {
    final lines = const LineSplitter().convert(text);
    for (var i = 0; i < lines.length; i++) {
      for (final delimiter in [';', ',', '\t']) {
        final csv = Csv(fieldDelimiter: delimiter, autoDetect: false);
        final header = csv.decode(lines[i]);
        if (header.isEmpty) continue;
        final names = header.first
            .map((v) => _normalize(v.toString()))
            .toList();
        int index(List<String> options) => names.indexWhere(options.contains);
        final date = index(['fecha', 'fecha movimiento']);
        final description = index(['descripcion', 'concepto', 'detalle']);
        final amount = index(['valor', 'monto', 'importe']);
        final debit = index(['debito', 'debitos']);
        final credit = index(['credito', 'creditos']);
        if (date < 0 ||
            description < 0 ||
            (amount < 0 && debit < 0 && credit < 0)) {
          continue;
        }
        double? initial, end;
        final rows = <ProposedTransaction>[];
        final data = csv.decode(text);
        for (final fields in data) {
          if (fields.isEmpty) continue;
          final first = _normalize(fields.first.toString());
          if (first.startsWith('saldo inicial') ||
              first.startsWith('saldo final')) {
            final raw = fields.length > 1
                ? fields[1].toString()
                : fields.first.toString().split(':').last;
            final balance = amountParser(raw);
            if (first.startsWith('saldo inicial')) {
              initial = balance;
            } else {
              end = balance;
            }
          }
        }
        for (final fields in csv.decode(lines.skip(i + 1).join('\n'))) {
          if (fields.isEmpty ||
              _normalize(fields.first.toString()).startsWith('saldo final')) {
            continue;
          }
          String field(int n) =>
              n < 0 || n >= fields.length ? '' : fields[n].toString().trim();
          if (fields.every((v) => v.toString().trim().isEmpty)) continue;
          final parsedDate = _date(field(date));
          final title = field(description);
          double? value;
          if (amount >= 0) {
            value = amountParser(field(amount));
          } else {
            final d = field(debit);
            final c = field(credit);
            final dv = d.isEmpty ? 0.0 : amountParser(d);
            final cv = c.isEmpty ? 0.0 : amountParser(c);
            if (dv != null && cv != null && !(dv != 0 && cv != 0)) {
              value = cv.abs() - dv.abs();
            }
          }
          if (parsedDate == null ||
              title.isEmpty ||
              value == null ||
              value == 0) {
            return null;
          }
          rows.add(
            ProposedTransaction(
              date: parsedDate,
              title: title,
              amount: value.abs(),
              type: value > 0
                  ? TransactionType.income
                  : TransactionType.expense,
              accountId: accountId,
            ),
          );
        }
        if (rows.isEmpty) return null;
        return StatementResult(rows, initial, end);
      }
    }
    return null;
  }

  /// Proposes a category for each row without one: one call per batch of
  /// [_categoryBatch] rows. Never throws. When the AI is not configured or a
  /// call fails, the rows keep no category and the result is flagged.
  Future<StatementResult> proposeCategories(StatementResult result) async {
    final pending = [
      for (final row in result.rows)
        if (row.categoryId == null) row,
    ];
    if (pending.isEmpty) return result;
    try {
      final catalog = await catalogLoader();
      final types = CategoryType.values.asNameMap();
      final categories = {
        for (final category in catalog.categories)
          category.id: types[category.type],
      };
      final client =
          await (clientLoader?.call() ?? AiService.instance.client());
      for (var start = 0; start < pending.length; start += _categoryBatch) {
        final batch = pending.skip(start).take(_categoryBatch).toList();
        final answer = await client.chat([
          AiMessage.system(
            'Asigna a cada fila de un extracto una categoría del catálogo. Devuelve JSON: {"rows":[{"i":0,"categoryId":"id"}]}. Usa solo ids del catálogo. Signo - es gasto (tipo E), signo + es ingreso (tipo I); B vale para ambos. Si no sabes, omite la fila. Catálogo: ${catalog.toPromptJson()}',
          ),
          AiMessage.user(
            jsonEncode([
              for (var i = 0; i < batch.length; i++)
                {
                  'i': i,
                  'fecha': batch[i].date.toIso8601String().split('T').first,
                  'descripcion': batch[i].title,
                  'signo': batch[i].type == TransactionType.income ? '+' : '-',
                },
            ]),
          ),
        ]);
        final list = answer.json()['rows'];
        if (list is! List) throw const FormatException('Missing rows');
        for (final value in list) {
          if (value is! Map || value['i'] is! int) continue;
          final i = value['i'] as int;
          final categoryId = value['categoryId'];
          if (i < 0 || i >= batch.length || categoryId is! String) continue;
          final type = categories[categoryId];
          if (type == null || !type.matchWithTransactionType(batch[i].type)) {
            continue;
          }
          batch[i].categoryId = categoryId;
        }
      }
      return result;
    } on Exception {
      return StatementResult(
        result.rows,
        result.initialBalance,
        result.finalBalance,
        categoryWarning: true,
      );
    }
  }

  Future<StatementResult> parseWithAi(String text, String accountId) async {
    final catalog = await catalogLoader();
    final client = await (clientLoader?.call() ?? AiService.instance.client());
    final rows = <ProposedTransaction>[];
    double? initial, end;
    for (var start = 0; start < text.length;) {
      var stop = (start + 12000).clamp(0, text.length);
      if (stop < text.length) {
        final newline = text.lastIndexOf('\n', stop);
        if (newline > start) stop = newline + 1;
      }
      final chunk = text.substring(start, stop);
      start = stop;
      final answer = await client.chat([
        AiMessage.system(
          'Extrae todas las transacciones del extracto sin inventar. Devuelve JSON: {"filas":[{"fecha":"dd/mm/aaaa","descripcion":"...","valor":"importe firmado"}],"saldo_inicial":"importe o null","saldo_final":"importe o null"}. Gastos negativos, ingresos positivos. Importes como aparecen; no incluyas saldos como movimientos. Catálogo: ${catalog.toPromptJson()}',
        ),
        AiMessage.user(chunk),
      ]);
      final json = answer.json();
      final list = json['filas'];
      if (list is! List) throw const FormatException('Missing rows');
      for (final value in list) {
        if (value is! Map ||
            value['fecha'] == null ||
            value['descripcion'] is! String ||
            value['valor'] == null) {
          throw const FormatException('Invalid row');
        }
        final date = _date(value['fecha'].toString());
        final title = (value['descripcion'] as String).trim();
        final amount = amountParser(value['valor'].toString());
        if (date == null || title.isEmpty || amount == null || amount == 0) {
          throw const FormatException('Invalid row');
        }
        rows.add(
          ProposedTransaction(
            date: date,
            title: title,
            amount: amount.abs(),
            type: amount > 0 ? TransactionType.income : TransactionType.expense,
            accountId: accountId,
          ),
        );
      }
      double? balance(String key) {
        final raw = json[key];
        if (raw == null) return null;
        return amountParser(raw.toString()) ??
            (throw const FormatException('Invalid balance'));
      }

      final first = balance('saldo_inicial');
      final last = balance('saldo_final');
      if (first != null) {
        if (initial != null && initial != first) {
          throw const FormatException('Conflicting balances');
        }
        initial = first;
      }
      if (last != null) {
        if (end != null && end != last) {
          throw const FormatException('Conflicting balances');
        }
        end = last;
      }
    }
    if (rows.isEmpty) throw const FormatException('No rows');
    return StatementResult(rows, initial, end);
  }

  Future<String> save({
    required StatementResult result,
    required String label,
    required String text,
    required String note,
  }) => (inbox ?? InboxService.instance).addItem(
    InboxDraft(
      source: InboxSource.statement,
      sourceRef: label,
      proposals: result.rows,
      rawText: text,
      note: note,
    ),
  );
}
