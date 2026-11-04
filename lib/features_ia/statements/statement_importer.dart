import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/core/privacy/statement_redaction.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:pdfrx/pdfrx.dart';

typedef AmountParser = double? Function(String);

/// Characters of statement text per AI call.
const _chunkSize = 12000;

/// Added to the request when the first reading did not reconcile with the balances.
const _reviewInstruction =
    ' La lectura anterior no cuadró: el neto de los movimientos debe cuadrar con el saldo inicial y el final; revisa filas y signos.';

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

  /// Rows whose category is missing or does not fit their type: the ones the AI would be asked about.
  List<ProposedTransaction> _rowsWithoutCategory(
    StatementResult result,
    AiCatalog catalog,
  ) {
    final types = CategoryType.values.asNameMap();
    final categories = {
      for (final category in catalog.categories)
        category.id: types[category.type],
    };
    bool fits(ProposedTransaction row) {
      final category = categories[row.categoryId];
      return category != null && category.matchWithTransactionType(row.type);
    }

    return [
      for (final row in result.rows)
        if (!fits(row)) row,
    ];
  }

  /// The user message of one batch of rows sent to propose categories: masked descriptions and signs only.
  String _categoryRowsText(List<ProposedTransaction> batch) => jsonEncode([
    for (var i = 0; i < batch.length; i++)
      {
        'i': i,
        'descripcion': maskStatementIdentifiers(batch[i].title),
        'signo': batch[i].type == TransactionType.income ? '+' : '-',
      },
  ]);

  /// Exactly what [proposeCategories] would send for [result], one block per call, or null when no row needs a category.
  Future<String?> categoryPreview(StatementResult result) async {
    final pending = _rowsWithoutCategory(result, await catalogLoader());
    if (pending.isEmpty) return null;
    return [
      for (var start = 0; start < pending.length; start += _categoryBatch)
        _categoryRowsText(pending.skip(start).take(_categoryBatch).toList()),
    ].join('\n\n');
  }

  /// Proposes a category for each row without a valid one (an id of the catalog
  /// whose type fits the row), one call per batch of [_categoryBatch] rows.
  /// Never throws. When the AI is not configured or a call fails, the rows keep
  /// no category and the result is flagged.
  Future<StatementResult> proposeCategories(StatementResult result) async {
    try {
      final catalog = await catalogLoader();
      final types = CategoryType.values.asNameMap();
      final categories = {
        for (final category in catalog.categories)
          category.id: types[category.type],
      };
      final pending = _rowsWithoutCategory(result, catalog);
      for (final row in pending) {
        row.categoryId = null;
      }
      if (pending.isEmpty) return result;
      final client =
          await (clientLoader?.call() ?? aiClientFor(AiFeature.statement));
      for (var start = 0; start < pending.length; start += _categoryBatch) {
        final batch = pending.skip(start).take(_categoryBatch).toList();
        final answer = await client.chatWithCap([
          AiMessage.system(
            'Asigna a cada fila de un extracto una categoría del catálogo. Devuelve JSON: {"rows":[{"i":0,"categoryId":"id"}]}. Usa solo ids del catálogo. Signo - es gasto (tipo E), signo + es ingreso (tipo I); B vale para ambos. Si no sabes, omite la fila. Catálogo: ${catalog.categoriesForPrompt()}',
          ),
          AiMessage.user(_categoryRowsText(batch)),
        ], maxTokens: AiTokenCaps.categorize);
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

  /// The text [parseWithAi] sends for [fullText]: reduced and masked. Shown to the user before sending.
  String textToSend(String fullText) => redactStatementText(fullText);

  /// Reads the statement with the AI. The provider receives only the movement lines of [fullText] (or, when the table
  /// is not found, the whole text without the holder, address and document lines), with account, card and document
  /// numbers, emails and phones masked, and no catalog: the account is the one the user chose.
  /// When the reading does not reconcile with the statement's balances, it is asked once more with exactly the same
  /// masked text plus a review instruction, and the reading that reconciles is kept (the first one when neither does).
  /// Never more than two calls, so the retry only happens when the text fits in one request.
  /// [approvedText] is the text the user saw and accepted (see [textToSend]); it is sent as it is.
  Future<StatementResult> parseWithAi(
    String fullText,
    String accountId, {
    String? approvedText,
  }) async {
    final client =
        await (clientLoader?.call() ?? aiClientFor(AiFeature.statement));
    final text = approvedText ?? textToSend(fullText);
    final first = await _readWithAi(client, text, accountId);
    if (_reconciles(first) || text.length > _chunkSize) return first;
    try {
      final second = await _readWithAi(client, text, accountId, review: true);
      return _reconciles(second) ? second : first;
    } on Exception {
      return first;
    }
  }

  /// True when there is nothing to retry: no balances to compare, or the difference is zero.
  bool _reconciles(StatementResult result) {
    final difference = result.difference;
    return difference == null || difference.abs() < 0.005;
  }

  Future<StatementResult> _readWithAi(
    AiClient client,
    String text,
    String accountId, {
    bool review = false,
  }) async {
    final rows = <ProposedTransaction>[];
    double? initial, end;
    for (var start = 0; start < text.length;) {
      var stop = (start + _chunkSize).clamp(0, text.length);
      if (stop < text.length) {
        final newline = text.lastIndexOf('\n', stop);
        if (newline > start) stop = newline + 1;
      }
      final chunk = text.substring(start, stop);
      start = stop;
      final answer = await client.chatWithCap([
        AiMessage.system(
          'Extrae todas las transacciones del extracto sin inventar. Devuelve JSON: {"filas":[{"fecha":"dd/mm/aaaa","descripcion":"...","valor":"importe firmado"}],"saldo_inicial":"importe o null","saldo_final":"importe o null"}. Gastos negativos, ingresos positivos. Importes como aparecen; no incluyas saldos como movimientos. Los datos personales aparecen ocultos entre corchetes, por ejemplo [id]: déjalos así.${review ? _reviewInstruction : ''}',
        ),
        AiMessage.user(chunk),
      ], maxTokens: AiTokenCaps.statement);
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

  /// Saves the rows as an inbox item. The net and the difference with the bank's balances go in the item's [InboxDraft.data]
  /// (the difference only when both balances were read), so the review reads them without parsing [note].
  Future<String> save({
    required StatementResult result,
    required String label,
    required String text,
    required String note,
  }) {
    final difference = result.difference;
    return (inbox ?? InboxService.instance).addItem(
      InboxDraft(
        source: InboxSource.statement,
        sourceRef: label,
        proposals: result.rows,
        rawText: text,
        note: note,
        data: difference == null
            ? null
            : {
                InboxDataKeys.net: result.net,
                InboxDataKeys.difference: difference,
              },
      ),
    );
  }
}
