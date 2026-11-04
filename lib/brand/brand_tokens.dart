import 'package:flutter/material.dart';

/// Tokens of the "Durazno cálido" brand (docs/brand/MARCA.md). They are the
/// only source of color: widgets read them through the theme, never as hex.
class BrandPalette {
  const BrandPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceLow,
    required this.soft,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.text,
    required this.textSecondary,
    required this.outline,
    required this.expense,
    required this.income,
    required this.warning,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceLow;
  final Color soft;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color text;
  final Color textSecondary;
  final Color outline;
  final Color expense;
  final Color income;
  final Color warning;

  /// Text/background pairs that must reach 4.5:1, by token name. The contrast
  /// test walks this list.
  Map<String, (Color, Color)> get textPairs => {
    'text/background': (text, background),
    'text/surface': (text, surface),
    'text/surfaceLow': (text, surfaceLow),
    'text/soft': (text, soft),
    'textSecondary/background': (textSecondary, background),
    'textSecondary/surface': (textSecondary, surface),
    'textSecondary/surfaceLow': (textSecondary, surfaceLow),
    'onPrimary/primary': (onPrimary, primary),
    'onPrimaryContainer/primaryContainer': (
      onPrimaryContainer,
      primaryContainer,
    ),
    'primary/background': (primary, background),
    'primary/surface': (primary, surface),
    'expense/background': (expense, background),
    'expense/surface': (expense, surface),
    'income/background': (income, background),
    'income/surface': (income, surface),
    'warning/background': (warning, background),
    'warning/surface': (warning, surface),
  };

  BrandColors get extension => BrandColors(
    expense: expense,
    income: income,
    warning: warning,
    soft: soft,
    surfaceLow: surfaceLow,
    textSecondary: textSecondary,
    outline: outline,
  );
}

abstract final class BrandTokens {
  static const light = BrandPalette(
    brightness: Brightness.light,
    background: Color(0xFFFFF7F0),
    surface: Color(0xFFFFFFFF),
    surfaceLow: Color(0xFFFFF3EA),
    soft: Color(0xFFFFE3D3),
    primary: Color(0xFFBC4626),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFE3D3),
    onPrimaryContainer: Color(0xFF7A2E16),
    text: Color(0xFF2B2118),
    textSecondary: Color(0xFF6F6259),
    outline: Color(0xFFF0DCCD),
    expense: Color(0xFFC43D3D),
    income: Color(0xFF2A7A52),
    warning: Color(0xFFA15C07),
  );

  static const dark = BrandPalette(
    brightness: Brightness.dark,
    background: Color(0xFF1C1612),
    surface: Color(0xFF261E19),
    surfaceLow: Color(0xFF211A15),
    soft: Color(0xFF3A2A22),
    primary: Color(0xFFFF9F7A),
    onPrimary: Color(0xFF3A1406),
    primaryContainer: Color(0xFF5A2A18),
    onPrimaryContainer: Color(0xFFFFDCCB),
    text: Color(0xFFF6EDE6),
    textSecondary: Color(0xFFCDBDB2),
    outline: Color(0xFF3D2F27),
    expense: Color(0xFFFF8A80),
    income: Color(0xFF7DD3A8),
    warning: Color(0xFFF5B85C),
  );

  /// Default accent stored in the settings, as the hex the picker writes.
  static const accentHex = 'BC4626';

  /// Radii and spacing from MARCA.md.
  static const double cardRadius = 20;
  static const double fieldRadius = 16;
  static const double sheetRadius = 28;
  static const double buttonHeight = 48;
  static const double pageMargin = 20;

  /// Fixed mascot colors, equal in light and dark.
  static const chanchiBody = Color(0xFFFFB4A2);
  static const chanchiShadow = Color(0xFFF59C88);
  static const chanchiHighlight = Color(0xFFFFD3C7);
  static const chanchiLegs = Color(0xFFFFA48F);
  static const chanchiBackdrop = Color(0xFFF08F7A);
  static const chanchiSnout = Color(0xFFFF9F8A);
  static const chanchiMouth = Color(0xFFBC4626);
  static const chanchiCoin = Color(0xFFF2B544);

  /// Relative-luminance contrast ratio (WCAG) between two opaque colors.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// Semantic colors that the Material [ColorScheme] has no slot for.
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.expense,
    required this.income,
    required this.warning,
    required this.soft,
    required this.surfaceLow,
    required this.textSecondary,
    required this.outline,
  });

  final Color expense;
  final Color income;
  final Color warning;
  final Color soft;
  final Color surfaceLow;
  final Color textSecondary;
  final Color outline;

  static BrandColors of(BuildContext context) =>
      Theme.of(context).extension<BrandColors>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? BrandTokens.dark.extension
          : BrandTokens.light.extension);

  @override
  BrandColors copyWith({
    Color? expense,
    Color? income,
    Color? warning,
    Color? soft,
    Color? surfaceLow,
    Color? textSecondary,
    Color? outline,
  }) {
    return BrandColors(
      expense: expense ?? this.expense,
      income: income ?? this.income,
      warning: warning ?? this.warning,
      soft: soft ?? this.soft,
      surfaceLow: surfaceLow ?? this.surfaceLow,
      textSecondary: textSecondary ?? this.textSecondary,
      outline: outline ?? this.outline,
    );
  }

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      expense: Color.lerp(expense, other.expense, t)!,
      income: Color.lerp(income, other.income, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      surfaceLow: Color.lerp(surfaceLow, other.surfaceLow, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
    );
  }
}
