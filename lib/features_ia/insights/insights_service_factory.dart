// Factory of the real insights service (T002). Owner: w-insights.
import 'package:monekin/features_ia/insights/insights_data.dart';
import 'package:monekin/features_ia/insights/insights_service.dart';
import 'package:monekin/features_ia/insights/insights_service_impl.dart';

InsightsService createInsightsService() => InsightsServiceImpl(
  loadExpenses: loadExpensesFromMonekin,
  preferredCurrency: preferredCurrencyFromMonekin,
  languageName: insightsLanguageName,
);
