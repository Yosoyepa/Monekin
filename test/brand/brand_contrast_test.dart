import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/brand/brand_tokens.dart';

void main() {
  for (final entry in {
    'light': BrandTokens.light,
    'dark': BrandTokens.dark,
  }.entries) {
    group('contrast ${entry.key}', () {
      for (final pair in entry.value.textPairs.entries) {
        test('${pair.key} >= 4.5:1', () {
          final (fg, bg) = pair.value;
          expect(BrandTokens.contrast(fg, bg), greaterThanOrEqualTo(4.5));
        });
      }
    });
  }

  test('numbers quoted in MARCA.md hold', () {
    final l = BrandTokens.light;
    final d = BrandTokens.dark;
    expect(BrandTokens.contrast(l.primary, l.surface), closeTo(5.2, 0.15));
    expect(
      BrandTokens.contrast(l.textSecondary, l.background),
      closeTo(5.6, 0.15),
    );
    expect(BrandTokens.contrast(l.expense, l.surface), closeTo(5.1, 0.15));
    expect(BrandTokens.contrast(l.income, l.surface), closeTo(5.2, 0.15));
    expect(BrandTokens.contrast(d.onPrimary, d.primary), closeTo(8.2, 0.15));
  });
}
