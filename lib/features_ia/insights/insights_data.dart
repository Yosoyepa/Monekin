// Monekin data and local storage behind the insights (T002). Tests replace [InsightsData.debugOverride].
import 'dart:io';

import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/currency/currency_service.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:path_provider/path_provider.dart';

/// The last recommendations the user got, kept between app runs.
class SavedTips {
  const SavedTips({required this.savedAt, required this.tips});

  final DateTime savedAt;
  final List<String> tips;
}

class InsightsData {
  const InsightsData({
    required this.loadExpenses,
    required this.preferredCurrency,
    required this.loadLastTips,
    required this.saveLastTips,
  });

  /// Posted expenses in [start, end), in the preferred currency.
  final Future<List<InsightTransaction>> Function(DateTime start, DateTime end)
  loadExpenses;
  final Future<CurrencyInDB> Function() preferredCurrency;
  final Future<SavedTips?> Function() loadLastTips;
  final Future<void> Function(SavedTips saved) saveLastTips;

  /// Tests of the insights pages inject fakes here.
  static InsightsData? debugOverride;

  static InsightsData get current => debugOverride ?? monekin;

  static final monekin = InsightsData(
    loadExpenses: loadExpensesFromMonekin,
    preferredCurrency: preferredCurrencyFromMonekin,
    loadLastTips: _loadLastTips,
    saveLastTips: _saveLastTips,
  );
}

/// Posted expenses in [start, end) from Monekin. Transfers and unposted rows are left out.
Future<List<InsightTransaction>> loadExpensesFromMonekin(
  DateTime start,
  DateTime end,
) async {
  final rows = await TransactionService.instance
      .getTransactions(
        filters: TransactionFilterSet(
          minDate: start,
          maxDate: end,
          transactionTypes: const [TransactionType.expense],
        ),
        onlyPosted: true,
      )
      .first;

  return [
    for (final tx in rows)
      InsightTransaction(
        title: tx.title ?? '',
        amount: -tx.currentValueInPreferredCurrency,
        date: tx.date,
        categoryId: tx.category?.id ?? '',
        categoryName: tx.category?.name ?? '',
      ),
  ];
}

Future<CurrencyInDB> preferredCurrencyFromMonekin() =>
    CurrencyService.instance.ensureAndGetPreferredCurrency().first;

/// English name of the app language, sent to the AI so it answers in the same language.
String insightsLanguageName() =>
    _languageNames[LocaleSettings.currentLocale.languageTag.split('-').first] ??
    'English';

const _languageNames = {
  'de': 'German',
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'hu': 'Hungarian',
  'it': 'Italian',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'zh': 'Chinese',
};

Future<File> _lastTipsFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}${Platform.pathSeparator}insights_last_tips.txt');
}

/// One line with the date, then one line per tip.
Future<SavedTips?> _loadLastTips() async {
  final file = await _lastTipsFile();
  if (!await file.exists()) return null;

  final lines = (await file.readAsLines())
      .where((line) => line.trim().isNotEmpty)
      .toList();
  final savedAt = lines.isEmpty ? null : DateTime.tryParse(lines.first);
  if (savedAt == null) return null;
  return SavedTips(savedAt: savedAt, tips: lines.skip(1).toList());
}

Future<void> _saveLastTips(SavedTips saved) async {
  final file = await _lastTipsFile();
  final tips = [
    for (final tip in saved.tips) tip.replaceAll(RegExp(r'\s+'), ' '),
  ];
  await file.writeAsString(
    [saved.savedAt.toIso8601String(), ...tips].join('\n'),
  );
}
