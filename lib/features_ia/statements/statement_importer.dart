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

/// The approval of one AI call chain over a statement is void: the catalog or the destination changed after the
/// preview. Nothing was sent; the user has to see a new preview.
class StatementApprovalChanged implements Exception {
  const StatementApprovalChanged();

  @override
  String toString() => 'StatementApprovalChanged';
}

/// Everything variable that one statement import sends to the AI provider, fixed when the preview is built:
/// the content (statement text, or rows to categorize), the categories of the catalog and the destination.
/// The importer sends this and nothing else, and only while the catalog and the destination are unchanged.
class StatementSend {
  StatementSend._({
    required this.reads,
    required this.config,
    required this.catalogJson,
    required this.categories,
    required this.content,
    required this.userTexts,
    this.batches = const [],
  });

  /// True when the AI reads a statement text; false when it only proposes categories for rows read locally.
  final bool reads;

  /// Provider, origin and model the user saw.
  final AiProviderConfig config;

  /// The catalog (id, name, type) as it goes in the system message of each request.
  final String catalogJson;
  final Map<String, CategoryType?> categories;

  /// The text, or the rows, shown to the user.
  final String content;

  /// The user message of each request.
  final List<String> userTexts;
  final List<List<ProposedTransaction>> batches;

  /// Exactly what leaves the phone besides fixed instructions: [content] and the catalog, with a heading each.
  String previewText({
    required String contentLabel,
    required String categoriesLabel,
  }) => '$contentLabel\n$content\n\n$categoriesLabel\n$catalogJson';
}

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

  /// The category ids of [catalog] and the transaction types each one fits.
  Map<String, CategoryType?> _categoryTypes(AiCatalog catalog) {
    final types = CategoryType.values.asNameMap();
    return {
      for (final category in catalog.categories)
        category.id: types[category.type],
    };
  }

  /// Rows whose category is missing or does not fit their type: the ones the AI would be asked about.
  List<ProposedTransaction> _rowsWithoutCategory(
    StatementResult result,
    Map<String, CategoryType?> categories,
  ) {
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

  /// [text] cut in the pieces sent one per call.
  List<String> _chunks(String text) {
    final chunks = <String>[];
    for (var start = 0; start < text.length;) {
      var stop = (start + _chunkSize).clamp(0, text.length);
      if (stop < text.length) {
        final newline = text.lastIndexOf('\n', stop);
        if (newline > start) stop = newline + 1;
      }
      chunks.add(text.substring(start, stop));
      start = stop;
    }
    return chunks;
  }

  /// What the AI would receive to read [fullText]: the reduced and masked text and the categories of the catalog.
  /// Show [StatementSend.previewText] to the user and hand the same object to [parseWithAi]: it sends nothing else.
  Future<StatementSend> prepareRead(String fullText) async {
    final catalog = await catalogLoader();
    final text = redactStatementText(fullText);
    return StatementSend._(
      reads: true,
      config: await currentAiConfig(),
      catalogJson: catalog.categoriesForPrompt(),
      categories: _categoryTypes(catalog),
      content: text,
      userTexts: _chunks(text),
    );
  }

  /// What the AI would receive to propose categories for the rows of [result] that have none (index, masked
  /// description and sign) and the categories of the catalog; null when every row has a valid category.
  Future<StatementSend?> prepareCategories(StatementResult result) async {
    final catalog = await catalogLoader();
    final categories = _categoryTypes(catalog);
    final pending = _rowsWithoutCategory(result, categories);
    if (pending.isEmpty) return null;
    final batches = [
      for (var start = 0; start < pending.length; start += _categoryBatch)
        pending.skip(start).take(_categoryBatch).toList(),
    ];
    final userTexts = [for (final batch in batches) _categoryRowsText(batch)];
    return StatementSend._(
      reads: false,
      config: await currentAiConfig(),
      catalogJson: catalog.categoriesForPrompt(),
      categories: categories,
      content: userTexts.join('\n\n'),
      userTexts: userTexts,
      batches: batches,
    );
  }

  /// The client of the approved [send], or [StatementApprovalChanged] when the catalog or the destination are no
  /// longer the ones the user saw: the approval is void and a new preview is needed.
  Future<AiClient> _approvedClient(StatementSend send) async {
    final catalog = await catalogLoader();
    if (catalog.categoriesForPrompt() != send.catalogJson ||
        aiDestinationOf(await currentAiConfig()) !=
            aiDestinationOf(send.config)) {
      throw const StatementApprovalChanged();
    }
    final client =
        await (clientLoader?.call() ?? aiClientFor(AiFeature.statement));
    if (client is GuardedAiClient &&
        aiDestinationOf(client.config) != aiDestinationOf(send.config)) {
      throw const StatementApprovalChanged();
    }
    return client;
  }

  /// Proposes a category for each row without a valid one (an id of the catalog whose type fits the row), one call
  /// per batch of [_categoryBatch] rows, with exactly what [send] (from [prepareCategories]) showed.
  /// Throws [StatementApprovalChanged] when the approval no longer holds; otherwise it never throws. When the AI is not
  /// configured or a call fails, the rows keep no category and the result is flagged.
  Future<StatementResult> proposeCategories(
    StatementResult result, {
    StatementSend? send,
  }) async {
    try {
      final approved = send ?? await prepareCategories(result);
      if (approved == null) return result;
      for (final batch in approved.batches) {
        for (final row in batch) {
          row.categoryId = null;
        }
      }
      final client = await _approvedClient(approved);
      for (var n = 0; n < approved.batches.length; n++) {
        final batch = approved.batches[n];
        final answer = await client.chatWithCap([
          AiMessage.system(
            'Asigna a cada fila de un extracto una categoría del catálogo. Devuelve JSON: {"rows":[{"i":0,"categoryId":"id"}]}. Usa solo ids del catálogo. Signo - es gasto (tipo E), signo + es ingreso (tipo I); B vale para ambos. Si no sabes, omite la fila. Catálogo: ${approved.catalogJson}',
          ),
          AiMessage.user(approved.userTexts[n]),
        ], maxTokens: AiTokenCaps.categorize);
        final list = answer.json()['rows'];
        if (list is! List) throw const FormatException('Missing rows');
        for (final value in list) {
          if (value is! Map || value['i'] is! int) continue;
          final i = value['i'] as int;
          final categoryId = value['categoryId'];
          if (i < 0 || i >= batch.length || categoryId is! String) continue;
          final type = approved.categories[categoryId];
          if (type == null || !type.matchWithTransactionType(batch[i].type)) {
            continue;
          }
          batch[i].categoryId = categoryId;
        }
      }
      return result;
    } on StatementApprovalChanged {
      rethrow;
    } on Exception {
      return StatementResult(
        result.rows,
        result.initialBalance,
        result.finalBalance,
        categoryWarning: true,
      );
    }
  }

  /// Reads the statement with the AI in one request per piece of [send] (from [prepareRead]), which also asks for the
  /// category of each row: there is no second request to categorize. The provider receives only what the user saw.
  /// When the reading does not reconcile with the statement's balances, it is asked once more with exactly the same
  /// masked text plus a review instruction, and the reading that reconciles is kept (the first one when neither does).
  /// Never more than two calls, so the retry only happens when the text fits in one request.
  /// Throws [StatementApprovalChanged] when the catalog or the destination changed since the preview.
  Future<StatementResult> parseWithAi(
    String fullText,
    String accountId, {
    StatementSend? send,
  }) async {
    final approved = send ?? await prepareRead(fullText);
    final client = await _approvedClient(approved);
    final first = await _readWithAi(client, approved, accountId);
    if (_reconciles(first) || approved.userTexts.length > 1) return first;
    try {
      final second = await _readWithAi(
        client,
        approved,
        accountId,
        review: true,
      );
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
    StatementSend send,
    String accountId, {
    bool review = false,
  }) async {
    final rows = <ProposedTransaction>[];
    double? initial, end;
    for (final chunk in send.userTexts) {
      final answer = await client.chatWithCap([
        AiMessage.system(
          'Extrae todas las transacciones del extracto sin inventar. Devuelve JSON: {"filas":[{"fecha":"dd/mm/aaaa","descripcion":"...","valor":"importe firmado","categoria":"id del catálogo o null"}],"saldo_inicial":"importe o null","saldo_final":"importe o null"}. Gastos negativos, ingresos positivos. Importes como aparecen; no incluyas saldos como movimientos. Los datos personales aparecen ocultos entre corchetes, por ejemplo [id]: déjalos así. En "categoria" usa solo ids del catálogo: tipo E para gastos, I para ingresos, B para ambos; si no sabes, null. Catálogo: ${send.catalogJson}${review ? _reviewInstruction : ''}',
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
        final type = amount > 0
            ? TransactionType.income
            : TransactionType.expense;
        final categoryId = value['categoria'];
        final fits =
            categoryId is String &&
            (send.categories[categoryId]?.matchWithTransactionType(type) ??
                false);
        rows.add(
          ProposedTransaction(
            date: date,
            title: title,
            amount: amount.abs(),
            type: type,
            categoryId: fits ? categoryId : null,
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
