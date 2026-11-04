import 'package:flutter/material.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/date-utils/date_period_state.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:monekin/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:monekin/core/presentation/widgets/trending_value.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:rxdart/rxdart.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Flat card with the total of one kind of flow (expenses or income): a tinted
/// icon, the label in the flow color and the amount.
class FlowSummaryCard extends StatelessWidget {
  const FlowSummaryCard({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.amount,
    required this.currency,
    this.trend,
    this.loading = false,
    this.onTap,
  });

  final String label;
  final IconData icon;

  /// `expense` or `income` from the brand tokens.
  final Color color;
  final double amount;

  /// Null while the preferred currency is still loading.
  final CurrencyInDB? currency;
  final Widget? trend;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoading = loading || currency == null;

    return PressScale(
      child: Material(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Skeletonizer(
                  enabled: isLoading,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: currency == null
                        ? Text('00000', style: theme.textTheme.headlineSmall)
                        : CurrencyDisplayer(
                            amountToConvert: isLoading ? 9999 : amount,
                            currency: currency,
                            compactView: amount >= 100000,
                            showDecimals: false,
                            integerStyle: theme.textTheme.headlineSmall!
                                .copyWith(fontFeatures: tabularFigures),
                          ),
                  ),
                ),
                if (trend != null) ...[const SizedBox(height: 8), trend!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Expenses and income of the period, each with its trend against the
/// previous one.
class DashboardFlowCard extends StatelessWidget {
  const DashboardFlowCard({
    super.key,
    required this.type,
    required this.color,
    required this.periodState,
    required this.currency,
    this.onTap,
  });

  final TransactionType type;
  final Color color;
  final DatePeriodState periodState;
  final CurrencyInDB? currency;
  final VoidCallback? onTap;

  TransactionFilterSet _filtersForDates(DateTime? min, DateTime? max) {
    return TransactionFilterSet(
      minDate: min,
      maxDate: max,
      transactionTypes: [type],
    );
  }

  Stream<double> _balanceStream(TransactionFilterSet filters) {
    return TransactionService.instance.getTransactionsValueBalance(
      filters: filters,
      convertToPreferredCurrency: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    final currentStream = _balanceStream(
      _filtersForDates(periodState.startDate, periodState.endDate),
    );

    final (prevStart, prevEnd) = periodState.getPrevDates();
    final canCompare = prevStart != null && prevEnd != null;

    final prevStream = canCompare
        ? _balanceStream(_filtersForDates(prevStart, prevEnd))
        : Stream.value(0.0);

    return StreamBuilder(
      stream: Rx.combineLatest2(
        currentStream,
        prevStream,
        (double current, double prev) => (current, prev),
      ),
      builder: (context, snapshot) {
        final hasData = snapshot.hasData;
        final current = (snapshot.data?.$1 ?? 0).abs();
        final prev = (snapshot.data?.$2 ?? 0).abs();

        return FlowSummaryCard(
          label: type.displayName(context),
          icon: type.icon,
          color: color,
          amount: current,
          currency: currency,
          loading: !hasData,
          onTap: onTap,
          trend: hasData && canCompare
              ? TrendingValue(
                  percentage: prev == 0 ? double.nan : (current - prev) / prev,
                  // A drop in expenses is the good direction.
                  inverse: type == TransactionType.expense,
                  style: TrendingValueStyle.chip,
                  afterText: t.home.vs_previous_period,
                  showPercentageDecimals: false,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                )
              : null,
        );
      },
    );
  }
}
