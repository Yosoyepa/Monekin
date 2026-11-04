// Shared pieces of the AI screens (phase 2 of the brand): soft notices, chips,
// cards and the Chanchi status view. Colors come from the theme and the brand
// tokens only.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';

enum IaTone { info, warning, error, success }

extension IaToneColor on IaTone {
  Color color(BuildContext context) {
    final brand = BrandColors.of(context);

    return switch (this) {
      IaTone.info => Theme.of(context).colorScheme.primary,
      IaTone.warning => brand.warning,
      IaTone.error => brand.expense,
      IaTone.success => brand.income,
    };
  }

  IconData get icon => switch (this) {
    IaTone.info => Icons.info_outline_rounded,
    IaTone.warning => Icons.warning_amber_rounded,
    IaTone.error => Icons.error_outline_rounded,
    IaTone.success => Icons.check_circle_outline_rounded,
  };
}

/// [tone] over the page surface, as a soft tint (no borders, no shadows).
Color iaTint(BuildContext context, Color tone, {double alpha = 0.12}) =>
    Color.alphaBlend(
      tone.withValues(alpha: alpha),
      Theme.of(context).colorScheme.surfaceContainerLowest,
    );

/// A soft card with an icon and a message. Warnings, info and errors.
class IaNotice extends StatelessWidget {
  const IaNotice({
    super.key,
    required this.text,
    this.tone = IaTone.warning,
    this.title,
    this.icon,
    this.margin = EdgeInsets.zero,
  });

  final String text;
  final String? title;
  final IaTone tone;
  final IconData? icon;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final color = tone.color(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: iaTint(context, color),
          borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon ?? tone.icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(text, style: textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill with an optional leading dot or icon.
class IaChip extends StatelessWidget {
  const IaChip({super.key, required this.label, this.color, this.icon});

  final String label;

  /// Accent of the dot or icon; the label keeps the text color for contrast.
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final accent = color ?? Theme.of(context).colorScheme.primary;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: brand.soft,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 14, color: accent)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 8),
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circle with an icon, in the soft container color.
class IaAvatar extends StatelessWidget {
  const IaAvatar({super.key, required this.icon, this.size = 48});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.of(context).soft,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, color: scheme.onPrimaryContainer, size: size * 0.5),
      ),
    );
  }
}

/// Flat card of the brand (radius 20, tone over the page, no shadow). With
/// [onTap] it presses down to 0.97 and ripples.
class IaCard extends StatelessWidget {
  const IaCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(BrandTokens.cardRadius);

    Widget card = Material(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );

    if (onTap != null) card = PressScale(child: card);

    return Padding(padding: margin, child: card);
  }
}

class IaSectionTitle extends StatelessWidget {
  const IaSectionTitle(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(top: 24, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

/// Chanchi with a title, a message and optional actions, centered. For empty,
/// loading and error states.
class IaStatusView extends StatelessWidget {
  const IaStatusView({
    super.key,
    required this.mood,
    this.title,
    this.message,
    this.actions = const [],
    this.size = 140,
    this.animate = true,
  });

  final ChanchiMood mood;
  final String? title;
  final String? message;
  final List<Widget> actions;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = BrandColors.of(context).textSecondary;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BrandTokens.pageMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChanchiMascot(mood: mood, size: size, animate: animate),
            const SizedBox(height: 16),
            if (title != null)
              Text(
                title!,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge,
              ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: secondary),
              ),
            ],
            for (final action in actions) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// A money amount with tabular figures, colored by sign when [signed].
class IaMoneyText extends StatelessWidget {
  const IaMoneyText(
    this.amount, {
    super.key,
    required this.format,
    this.income,
    this.style,
  });

  final double amount;
  final NumberFormat format;

  /// True for income (green), false for expense (red), null for neutral.
  final bool? income;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final base = style ?? Theme.of(context).textTheme.titleMedium;
    final color = switch (income) {
      true => brand.income,
      false => brand.expense,
      null => base?.color,
    };

    return Text(
      format.format(amount),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontFeatures: tabularFigures,
      ),
    );
  }
}

/// Formats amounts in the symbol and decimals of a currency, in the app locale.
NumberFormat iaMoneyFormat({String? symbol, int? decimals}) => symbol == null
    ? NumberFormat.decimalPattern()
    : NumberFormat.currency(symbol: symbol, decimalDigits: decimals ?? 2);
