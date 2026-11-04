import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monekin/app/home/widgets/balance_hero.dart';
import 'package:monekin/app/home/widgets/dashboard_account_list.dart';
import 'package:monekin/app/home/widgets/dashboard_balance_chart.dart';
import 'package:monekin/app/home/widgets/dashboard_greeting.dart';
import 'package:monekin/app/home/widgets/dashboard_layout.dart';
import 'package:monekin/app/home/widgets/finance_health_donut.dart';
import 'package:monekin/app/home/widgets/flow_summary_card.dart';
import 'package:monekin/app/home/widgets/new_transaction_fl_button.dart';
import 'package:monekin/app/home/widgets/period_chips.dart';
import 'package:monekin/app/home/widgets/private_mode_button.dart';
import 'package:monekin/app/layout/page_context.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/app/settings/widgets/edit_profile_modal.dart';
import 'package:monekin/app/stats/stats_page.dart';
import 'package:monekin/app/stats/widgets/movements_distribution/pie_chart_by_categories.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/account/account_service.dart';
import 'package:monekin/core/database/services/currency/currency_service.dart';
import 'package:monekin/core/database/services/user-setting/private_mode_service.dart';
import 'package:monekin/core/models/date-utils/date_period.dart';
import 'package:monekin/core/models/date-utils/date_period_state.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/presentation/debug_page.dart';
import 'package:monekin/core/presentation/helpers/snackbar.dart';
import 'package:monekin/core/presentation/responsive/breakpoints.dart';
import 'package:monekin/core/presentation/responsive/page_content.dart';
import 'package:monekin/core/presentation/widgets/card_with_header.dart';
import 'package:monekin/core/presentation/widgets/dates/date_period_modal.dart';
import 'package:monekin/core/presentation/widgets/dates/date_range_chips.dart';
import 'package:monekin/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:monekin/core/presentation/widgets/trending_value.dart';
import 'package:monekin/core/presentation/widgets/user_avatar.dart';
import 'package:monekin/core/presentation/widgets/user_profile_builder.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:rxdart/rxdart.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../core/database/services/app-data/app_data_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

typedef _BalanceStats = ({double delta, double percentage});

class _DashboardPageState extends State<DashboardPage> {
  DatePeriodState dateRangeService = const DatePeriodState(
    datePeriod: defaultDatePeriod,
  );
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showStickyBalanceHeader = ValueNotifier(false);
  late final Stream<double> _currentBalanceStream;
  late final Stream<CurrencyInDB> _preferredCurrency;
  late Stream<(double, _BalanceStats)> _balanceSummaryStream;

  @override
  void initState() {
    super.initState();

    _currentBalanceStream = AccountService.instance
        .getAccountsMoney()
        .distinct()
        .shareReplay(maxSize: 1);
    _preferredCurrency = CurrencyService.instance
        .ensureAndGetPreferredCurrency()
        .shareReplay(maxSize: 1);
    _refreshBalanceSummaryStream();
    _scrollController.addListener(_updateStickyBalanceHeader);
    _loadSavedDatePeriod();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateStickyBalanceHeader);
    _scrollController.dispose();
    _showStickyBalanceHeader.dispose();
    super.dispose();
  }

  Future<void> _loadSavedDatePeriod() async {
    final savedPeriodJson = appStateData[AppDataKey.lastDashboardDatePeriod];

    if (savedPeriodJson != null) {
      try {
        final period = DatePeriod.fromJsonString(savedPeriodJson);
        if (!mounted) return;
        setState(() {
          dateRangeService = dateRangeService.copyWith(datePeriod: period);
          _refreshBalanceSummaryStream();
        });
      } catch (_) {
        // Fall back to default
      }
    }
  }

  Stream<_BalanceStats> _getBalanceStatsStream(DatePeriodState dateRange) {
    final start = dateRange.startDate;
    final end = dateRange.endDate;

    if (start == null || end == null) {
      return Stream.value((delta: 0, percentage: 0));
    }

    return Rx.combineLatest2(
      AccountService.instance.getAccountsMoney(date: start),
      AccountService.instance.getAccountsMoney(date: end),
      (double startBalance, double endBalance) {
        final delta = endBalance - startBalance;

        const eps = 1e-10;
        final percentage = startBalance.abs() < eps
            ? (endBalance.abs() < eps ? 0.0 : double.nan)
            : delta / startBalance;

        return (delta: delta, percentage: percentage);
      },
    );
  }

  void _refreshBalanceSummaryStream() {
    _balanceSummaryStream = Rx.combineLatest2(
      _currentBalanceStream,
      _getBalanceStatsStream(dateRangeService),
      (double current, _BalanceStats stats) => (current, stats),
    ).distinct().shareReplay(maxSize: 1);
  }

  void _onPeriodChanged(DatePeriod period) {
    AppDataService.instance.setItem(
      AppDataKey.lastDashboardDatePeriod,
      period.toJsonString(),
    );

    setState(() {
      dateRangeService = dateRangeService.copyWith(
        periodModifier: 0,
        datePeriod: period,
      );
      _refreshBalanceSummaryStream();
    });
  }

  void _updateStickyBalanceHeader() {
    if (!_scrollController.hasClients) return;

    final show = _scrollController.offset > 180;
    if (show != _showStickyBalanceHeader.value) {
      _showStickyBalanceHeader.value = show;
    }
  }

  Future<void> _openDatePeriodSelector() async {
    final period = await openDatePeriodModal(
      context,
      DatePeriodModal(initialDatePeriod: dateRangeService.datePeriod),
    );

    if (period != null) _onPeriodChanged(period);
  }

  Future<void> _togglePrivateMode() async {
    final privateMode =
        await PrivateModeService.instance.privateModeStream.first;

    PrivateModeService.instance.setPrivateMode(!privateMode);
    await HapticFeedback.lightImpact();

    MonekinSnackbar.success(
      SnackbarParams(
        !privateMode
            ? t.settings.security.private_mode_activated
            : t.settings.security.private_mode_deactivated,
      ),
    );
  }

  void _openStats() {
    RouteUtils.pushRoute(
      StatsPage(
        dateRangeService: dateRangeService,
        initialIndex: StatsTab.distribution,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final motion = BrandMotion.of(context);

    return PageFramework(
      title: t.home.title,
      enableAppBar: false,
      floatingActionButton: ifIsInTabs(context)
          ? null
          : NewTransactionButton(
              key: const Key('dashboard--new-transaction-button'),
              scrollController: _scrollController,
            ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 32),
              child: PageContent(child: _buildContent(context)),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: _showStickyBalanceHeader,
                child: _buildStickyBalanceHeader(context),
                builder: (context, showHeader, child) => IgnorePointer(
                  ignoring: !showHeader,
                  child: AnimatedSlide(
                    duration: motion.state,
                    curve: motion.enter,
                    offset: showHeader ? Offset.zero : const Offset(0, -1),
                    child: AnimatedOpacity(
                      duration: motion.state,
                      opacity: showHeader ? 1 : 0,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyBalanceHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      shape: Border(
        bottom: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BrandTokens.pageMargin,
          vertical: 8,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          spacing: 16,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.home.total_balance,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                  StreamBuilder<double>(
                    stream: _currentBalanceStream,
                    builder: (context, snapshot) => Skeletonizer(
                      enabled: !snapshot.hasData,
                      child: CurrencyDisplayer(
                        amountToConvert: snapshot.data ?? 9999,
                        integerStyle: theme.textTheme.titleLarge!.copyWith(
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FilledButton.icon(
                onPressed: _openDatePeriodSelector,
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(
                  dateRangeService.getText(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final isWide = BreakPoint.of(context).isLargerOrEqualTo(BreakpointID.md);
    final expenseColor = BrandColors.of(context).expense;
    final incomeColor = BrandColors.of(context).income;

    return StreamBuilder<CurrencyInDB>(
      stream: _preferredCurrency,
      builder: (context, currencySnapshot) {
        final currency = currencySnapshot.data;

        return DashboardLayout(
          header: _buildHeader(context),
          balance: _buildBalanceHero(
            context,
            currency,
            inset: isWide ? 24 : 20,
          ),
          expenseCard: DashboardFlowCard(
            type: TransactionType.expense,
            color: expenseColor,
            periodState: dateRangeService,
            currency: currency,
            onTap: _openStats,
          ),
          incomeCard: DashboardFlowCard(
            type: TransactionType.income,
            color: incomeColor,
            periodState: dateRangeService,
            currency: currency,
            onTap: _openStats,
          ),
          accounts: DashboardAccountList(
            dateRangeService: dateRangeService,
            maxRowsToShow: isWide ? 5 : 3,
          ),
          health: FinanceHealthCard(dateRangeService: dateRangeService),
          categories: _buildCategoriesCard(context),
          footer: kDebugMode
              ? TextButton(
                  onPressed: () => RouteUtils.pushRoute(const DebugPage()),
                  child: const Text('DEBUG PAGE'),
                )
              : null,
        );
      },
    );
  }

  // ------------------------- Header -------------------------

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: UserProfileBuilder(
            builder: (context, userName, avatar) => DashboardGreeting(
              greeting: welcomeGreeting(
                Translations.of(context),
                DateTime.now(),
              ),
              userName: userName,
              avatar: UserAvatar(avatar: avatar),
              onTap: () => RouteUtils.showResponsiveSheet(
                context: context,
                builder: (context) => const EditProfileModal(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PrivateModeButton(onPressed: _togglePrivateMode),
      ],
    );
  }

  // ---------------------- Balance hero ----------------------

  Widget _buildBalanceHero(
    BuildContext context,
    CurrencyInDB? currency, {
    required double inset,
  }) {
    final accent = Theme.of(context).colorScheme.primary;

    return StreamBuilder(
      stream: _balanceSummaryStream,
      builder: (context, snapshot) {
        final stats = snapshot.data?.$2;

        return BalanceHero(
          label: t.home.total_balance,
          balance: snapshot.data?.$1 ?? 0,
          currency: currency,
          loading: !snapshot.hasData,
          inset: inset,
          trend: stats == null || currency == null
              ? null
              : TrendingValue(
                  percentage: stats.percentage,
                  value: stats.delta,
                  valueCurrency: currency,
                  dataTypes: const [
                    TrendingValueDataType.value,
                    TrendingValueDataType.percentage,
                  ],
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  style: TrendingValueStyle.chip,
                  compactValue: stats.delta.abs() >= 100000,
                ),
          chart: DashboardBalanceChart(
            dateRange: dateRangeService,
            lineColor: accent,
          ),
          chips: PeriodChips(
            currentPeriod: dateRangeService.datePeriod,
            onPeriodSelected: _onPeriodChanged,
          ),
        );
      },
    );
  }

  Widget _buildCategoriesCard(BuildContext context) {
    return CardWithHeader(
      title: t.stats.by_categories,
      bodyPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      headerAction: CardHeaderAction(onTap: _openStats),
      body: PieChartByCategories(datePeriodState: dateRangeService),
    );
  }
}
