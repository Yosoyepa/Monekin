// Factory of the real insights service (T002). Owner: w-insights.
import 'package:monekin/core/database/services/currency/currency_service.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:monekin/features_ia/insights/insights_aggregates.dart';
import 'package:monekin/features_ia/insights/insights_service.dart';
import 'package:monekin/features_ia/insights/insights_service_impl.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

InsightsService createInsightsService() => InsightsServiceImpl(
  loadExpenses: _loadExpenses,
  preferredCurrency: () =>
      CurrencyService.instance.ensureAndGetPreferredCurrency().first,
  languageName: () =>
      _languageNames[LocaleSettings.currentLocale.languageTag
          .split('-')
          .first] ??
      'English',
);

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

/// Posted expenses in [start, end), in the preferred currency. Transfers and unposted rows are left out.
Future<List<InsightTransaction>> _loadExpenses(
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
