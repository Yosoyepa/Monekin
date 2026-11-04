// Contract of the insights service (T002). Owner: w-insights. Used by the weekly notification (w-avisos).
class WeeklySummary {
  const WeeklySummary({required this.title, required this.body});

  final String title;
  final String body;
}

abstract class InsightsService {
  /// Replaced at startup by `initFeaturesIa()`.
  static InsightsService instance = NotReadyInsightsService();

  /// Short summary of the last seven days with one recommendation, or null when there is nothing to say.
  Future<WeeklySummary?> weeklySummary();
}

class NotReadyInsightsService implements InsightsService {
  @override
  Future<WeeklySummary?> weeklySummary() async => null;
}
