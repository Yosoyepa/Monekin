import 'package:flutter/material.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:monekin/core/presentation/widgets/number_ui_formatters/ui_number_formatter.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Total balance of the dashboard: label, the amount counting up to its value,
/// the trend, the evolution chart and the period chips.
class BalanceHero extends StatelessWidget {
  const BalanceHero({
    super.key,
    required this.label,
    required this.balance,
    required this.currency,
    required this.chart,
    required this.chips,
    this.trend,
    this.loading = false,
    this.inset = BrandTokens.pageMargin,
    this.chartHeight = 110,
  });

  final String label;
  final double balance;

  /// Null while the preferred currency is still loading.
  final CurrencyInDB? currency;
  final Widget chart;
  final Widget chips;
  final Widget? trend;
  final bool loading;

  /// Horizontal inset of the texts and chips; the chart runs full width.
  final double inset;
  final double chartHeight;

  String _format(double value) {
    final currency = this.currency;
    if (currency == null) return '';

    return UINumberFormatter.currency(
      amountToConvert: value,
      currency: currency,
    ).getFormattedAmount();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isLoading = loading || currency == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: textTheme.labelMedium),
              const SizedBox(height: 4),
              Skeletonizer(
                enabled: isLoading,
                child: BlurBasedOnPrivateMode(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: isLoading
                        ? Text('0000000', style: textTheme.displaySmall)
                        : CountUpText(
                            value: balance,
                            format: _format,
                            style: textTheme.displaySmall,
                          ),
                  ),
                ),
              ),
              if (trend != null) ...[const SizedBox(height: 8), trend!],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: chartHeight,
          child: RepaintBoundary(child: ClipRect(child: chart)),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: chips,
        ),
      ],
    );
  }
}
