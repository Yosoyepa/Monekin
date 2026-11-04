// Card map: last four digits -> Monekin account id (T002). Owner: w-utils.
// Stored in a JSON file in the app documents dir; it never holds full card numbers.
class CardMapService {
  CardMapService._();

  static final CardMapService instance = CardMapService._();

  Future<Map<String, String>> load() => throw UnimplementedError('CardMapService is implemented by w-utils');

  Future<void> save(Map<String, String> last4ToAccountId) =>
      throw UnimplementedError('CardMapService is implemented by w-utils');

  /// Account id for a card ending in [last4], or null.
  Future<String?> accountFor(String last4) => throw UnimplementedError('CardMapService is implemented by w-utils');
}
