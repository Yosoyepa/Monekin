import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/database/services/user-setting/enum/app-fonts.enum.dart';
import 'package:monekin/core/database/services/user-setting/user_setting_service.dart';
import 'package:monekin/core/extensions/color.extensions.dart';
import 'package:monekin/core/utils/app_utils.dart';

import 'app_colors.dart';

bool isAppUsingDynamicColors = false;

bool isAppInDarkBrightness(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;
bool isAppInLightBrightness(BuildContext context) =>
    !isAppInDarkBrightness(context);

double getCardBorderRadius() => BrandTokens.cardRadius;

extension TextThemeExtension on TextTheme {
  /// Returns a new [TextTheme] where selected body and label text styles have their
  /// color updated to the specified [color].
  ///
  /// The styles affected by this change are:
  /// - [bodyLarge]
  /// - [bodyMedium]
  /// - [bodySmall]
  /// - [labelMedium]
  /// - [labelSmall]
  TextTheme withDifferentBodyColors(Color color) {
    TextStyle? applyColor(TextStyle? style) => style?.copyWith(color: color);

    return copyWith(
      bodyLarge: applyColor(bodyLarge),
      bodyMedium: applyColor(bodyMedium),
      bodySmall: applyColor(bodySmall),
      labelMedium: applyColor(labelMedium),
      labelSmall: applyColor(labelSmall),
    );
  }
}

/// Brand [ColorScheme]: the page uses `background` as Material's `surface`,
/// and the surface/soft tones fill the container slots.
ColorScheme _brandScheme(BrandPalette p, {required bool amoled}) {
  final opposite = p.brightness == Brightness.dark
      ? BrandTokens.light
      : BrandTokens.dark;

  return ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.primaryContainer,
    onPrimaryContainer: p.onPrimaryContainer,
    secondary: p.primary,
    onSecondary: p.onPrimary,
    secondaryContainer: p.soft,
    onSecondaryContainer: p.onPrimaryContainer,
    tertiary: p.income,
    onTertiary: p.background,
    tertiaryContainer: p.soft,
    onTertiaryContainer: p.text,
    error: p.expense,
    onError: p.brightness == Brightness.dark ? p.background : Colors.white,
    errorContainer: p.soft,
    onErrorContainer: p.text,
    surface: amoled ? Colors.black : p.background,
    onSurface: p.text,
    onSurfaceVariant: p.textSecondary,
    outline: p.textSecondary,
    outlineVariant: p.outline,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: p.text,
    onInverseSurface: p.background,
    inversePrimary: opposite.primary,
    surfaceTint: Colors.transparent,
    surfaceDim: p.background,
    surfaceBright: p.surface,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surfaceLow,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.soft,
    surfaceContainerHighest: p.soft,
  );
}

/// Takes the accent slots from a seed, keeping the brand surfaces and text.
ColorScheme _withAccent(ColorScheme base, Color seed) {
  final accent = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: base.brightness,
  );
  return base.copyWith(
    primary: accent.primary,
    onPrimary: accent.onPrimary,
    primaryContainer: accent.primaryContainer,
    onPrimaryContainer: accent.onPrimaryContainer,
    secondary: accent.primary,
    onSecondary: accent.onPrimary,
  );
}

TextTheme _brandTextTheme(
  TextTheme base, {
  required Color text,
  required Color textSecondary,
}) {
  TextStyle s(
    TextStyle? from, {
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    Color? color,
    bool tabular = false,
  }) => (from ?? const TextStyle()).copyWith(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? text,
    fontFeatures: tabular ? tabularFigures : null,
  );

  return base.copyWith(
    displaySmall: s(
      base.displaySmall,
      size: 36,
      weight: FontWeight.w800,
      letterSpacing: -0.5,
      tabular: true,
    ),
    headlineSmall: s(base.headlineSmall, size: 24, weight: FontWeight.w800),
    titleLarge: s(base.titleLarge, size: 18, weight: FontWeight.w700),
    titleMedium: s(base.titleMedium, size: 16, weight: FontWeight.w700),
    titleSmall: s(base.titleSmall, size: 14, weight: FontWeight.w700),
    bodyLarge: s(
      base.bodyLarge,
      size: 16,
      weight: FontWeight.w400,
      height: 1.45,
    ),
    bodyMedium: s(
      base.bodyMedium,
      size: 14,
      weight: FontWeight.w400,
      height: 1.45,
    ),
    bodySmall: s(
      base.bodySmall,
      size: 12.5,
      weight: FontWeight.w400,
      height: 1.4,
      color: textSecondary,
    ),
    labelLarge: s(base.labelLarge, size: 14, weight: FontWeight.w700),
    labelMedium: s(
      base.labelMedium,
      size: 12.5,
      weight: FontWeight.w600,
      color: textSecondary,
    ),
    labelSmall: s(
      base.labelSmall,
      size: 12,
      weight: FontWeight.w600,
      color: textSecondary,
    ),
  );
}

/// Fade plus a 0.98 → 1 scale; entrances use the brand curve and exits last
/// 70% of the entrance. With reduced motion only a short fade remains.
class BrandPageTransitionsBuilder extends PageTransitionsBuilder {
  const BrandPageTransitionsBuilder();

  @override
  Duration get transitionDuration => BrandDurations.page;

  @override
  Duration get reverseTransitionDuration =>
      BrandDurations.exitOf(BrandDurations.page);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (BrandMotion.of(context).reduce) {
      final fadeEnd =
          BrandDurations.reducedFade.inMicroseconds /
          BrandDurations.page.inMicroseconds;
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Interval(0, fadeEnd),
        ),
        child: child,
      );
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: BrandCurves.enter,
      reverseCurve: BrandCurves.exit,
    );

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

ThemeData getThemeData(
  BuildContext context, {
  required bool isDark,
  required bool amoledMode,
  required ColorScheme? lightDynamic,
  required ColorScheme? darkDynamic,
  required String accentColor,
}) {
  final palette = isDark ? BrandTokens.dark : BrandTokens.light;
  final amoled = isDark && amoledMode;

  late final ColorScheme scheme;
  late final BrandColors brandColors;

  if (lightDynamic != null && darkDynamic != null && accentColor == 'auto') {
    // Dynamic colors (Material You) are an opt-in; the brand is the default.
    final dynamicSeed = isDark ? darkDynamic.primary : lightDynamic.primary;
    final seeded = ColorScheme.fromSeed(
      seedColor: dynamicSeed,
      brightness: palette.brightness,
      surface: isDark
          ? (amoled ? Colors.black : dynamicSeed.darkenPastel(amount: 0.92))
          : dynamicSeed.lightenPastel(amount: 0.91),
    );
    scheme = isDark ? seeded : seeded.harmonized();
    brandColors = palette.extension.copyWith(
      soft: scheme.primaryContainer,
      surfaceLow: scheme.surfaceContainerLow,
      textSecondary: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant,
    );
    isAppUsingDynamicColors = true; // ignore, only for demo purposes
  } else {
    final accentHex = accentColor == 'auto'
        ? BrandTokens.accentHex
        : accentColor.toUpperCase().replaceAll('#', '');
    final base = _brandScheme(palette, amoled: amoled);
    final isBrandAccent = accentHex == BrandTokens.accentHex;

    scheme = isBrandAccent ? base : _withAccent(base, ColorHex.get(accentHex));
    brandColors = palette.extension;
  }

  final customAppColors = _appColors(scheme, brandColors);

  final fontFamily =
      AppFonts.fromDB(appStateSettings[SettingKey.font])?.fontFamilyName ??
      AppFonts.nunito.fontFamilyName;

  final base = ThemeData(
    colorScheme: scheme,
    brightness: palette.brightness,
    useMaterial3: true,
    fontFamily: fontFamily,
    extensions: [customAppColors, brandColors],
  );

  final textTheme = _brandTextTheme(
    base.textTheme,
    text: scheme.onSurface,
    textSecondary: brandColors.textSecondary,
  );

  const pill = StadiumBorder();
  const buttonPadding = EdgeInsets.symmetric(horizontal: 24);
  final buttonText = textTheme.labelLarge!;
  const minSize = Size(64, BrandTokens.buttonHeight);

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    cardColor: scheme.surfaceContainerLowest,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const BrandPageTransitionsBuilder(),
      },
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minSize,
        padding: buttonPadding,
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: minSize,
        padding: buttonPadding,
        shape: pill,
        textStyle: buttonText,
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        padding: buttonPadding,
        shape: pill,
        textStyle: buttonText,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: minSize,
        padding: buttonPadding,
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    dividerTheme: DividerThemeData(
      space: 0,
      thickness: 1,
      color: scheme.outlineVariant,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      hintStyle: TextStyle(color: brandColors.textSecondary),
      helperStyle: TextStyle(color: brandColors.textSecondary),
      border: inputBorder,
      enabledBorder: inputBorder,
      disabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: brandColors.expense),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: brandColors.expense, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide.none,
      backgroundColor: brandColors.soft,
      selectedColor: scheme.primaryContainer,
      disabledColor: brandColors.surfaceLow,
      labelStyle: buttonText,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 0,
      pressElevation: 0,
      showCheckmark: false,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: pill,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      elevation: 0,
      backgroundColor: scheme.surfaceContainer,
      modalBackgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      dragHandleSize: const Size(32, 4),
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BrandTokens.sheetRadius),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: pill,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : brandColors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelSmall!.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : brandColors.textSecondary,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.sheetRadius),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium!.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: scheme.inversePrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
    scrollbarTheme: AppUtils.isDesktop
        ? ScrollbarThemeData(
            thumbVisibility: const WidgetStatePropertyAll(true),
            thickness: const WidgetStatePropertyAll(7),
            radius: const Radius.circular(4),
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => scheme.onSurfaceVariant.withValues(
                alpha: states.contains(WidgetState.hovered) ? 0.7 : 0.45,
              ),
            ),
          )
        : null,
    // On desktop, icon buttons feel more native as compact, slightly-rounded
    // squares instead of the large fully-circular touch targets.
    iconButtonTheme: AppUtils.isDesktop
        ? IconButtonThemeData(
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(34, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          )
        : null,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: textTheme.headlineSmall,
      // On desktop, app bars read as flat toolbars separated from the content
      // by a subtle bottom hairline, with icon buttons kept off the edge.
      actionsPadding: AppUtils.isDesktop
          ? const EdgeInsetsDirectional.only(end: 12)
          : null,
      shape: AppUtils.isDesktop
          ? Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            )
          : null,
    ),
  );
}

/// Keeps the upstream [AppColors] extension, fed with brand values.
AppColors _appColors(ColorScheme scheme, BrandColors brand) {
  final base = AppColors.fromColorScheme(scheme);

  return base.copyWith(
    colors: {
      ...base.colors,
      'danger': brand.expense,
      'success': brand.income,
      'brand': scheme.primary,
      'textBody': scheme.onSurface,
      'textHint': brand.textSecondary,
      'modalBackground': scheme.surfaceContainer,
    },
  );
}
