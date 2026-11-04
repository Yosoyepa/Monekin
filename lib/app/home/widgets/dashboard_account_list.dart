import 'package:flutter/material.dart';
import 'package:monekin/app/accounts/account_form.dart';
import 'package:monekin/app/accounts/all_accounts_page.dart';
import 'package:monekin/app/accounts/details/account_details.dart';
import 'package:monekin/app/accounts/widgets/account_group.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/database/services/account/account_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/date-utils/date_period_state.dart';
import 'package:monekin/core/models/supported-icon/supported_icon.dart';
import 'package:monekin/core/services/supported_icon/supported_icon_service.dart';
import 'package:monekin/core/presentation/widgets/card_with_header.dart';
import 'package:monekin/core/presentation/widgets/no_results.dart';
import 'package:monekin/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:monekin/core/presentation/widgets/trending_value.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// A vertical list of the user's active accounts, where the accounts sharing a
/// group are collapsed into an expandable row.
class DashboardAccountList extends StatelessWidget {
  const DashboardAccountList({
    super.key,
    required this.dateRangeService,
    this.maxRowsToShow = 3,
  });

  final DatePeriodState dateRangeService;
  final int maxRowsToShow;

  void _openCreateAccountForm() {
    RouteUtils.showResponsiveForm(const AccountFormPage());
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return StreamBuilder(
      stream: AccountService.instance.getAccounts(
        predicate: (acc, curr) => acc.closingDate.isNull(),
      ),
      builder: (context, snapshot) {
        final accounts = snapshot.data;
        final rows = accounts == null ? null : groupAccounts(accounts);
        final isEmpty = rows != null && rows.isEmpty;
        final hasHiddenRows = (rows?.length ?? 0) > maxRowsToShow;

        return CardWithHeader(
          title: t.home.my_accounts,
          bodyPadding: isEmpty
              ? EdgeInsets.zero
              : const EdgeInsets.only(top: 4, bottom: 8),
          headerAction: CardHeaderAction(
            icon: const Icon(Icons.add_rounded),
            text: t.account.form.create,
            onTap: _openCreateAccountForm,
          ),
          footer: hasHiddenRows
              ? CardFooterWithSingleButton(
                  text: t.ui_actions.see_all_count(n: accounts!.length),
                  onButtonClick: () =>
                      RouteUtils.pushRoute(const AllAccountsPage()),
                )
              : null,
          body: _buildBody(context, rows),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, List<AccountRowData>? rows) {
    final t = Translations.of(context);

    if (rows == null) {
      return Column(
        children: [
          for (var i = 0; i < maxRowsToShow; i++) const _AccountRowSkeleton(),
        ],
      );
    }

    if (rows.isEmpty) {
      return NoResults(
        showIllustration: false,
        icon: Icons.account_balance_wallet_outlined,
        title: t.home.no_accounts,
        description: t.home.no_accounts_descr,
        bottom: TextButton.icon(
          onPressed: _openCreateAccountForm,
          icon: const Icon(Icons.add_rounded),
          label: Text(t.account.form.create),
        ),
      );
    }

    return Column(
      children: [
        for (final row in rows.take(maxRowsToShow))
          if (row.groupName == null || row.accounts.length == 1)
            _AccountRow(
              account: row.accounts.first,
              dateRangeService: dateRangeService,
            )
          else
            _AccountGroupRow(
              groupName: row.groupName!,
              accounts: row.accounts,
              dateRangeService: dateRangeService,
            ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.dateRangeService});

  final Account account;
  final DatePeriodState dateRangeService;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: AccountRowTile(
        leading: Hero(
          tag: 'dashboard-page__account-icon-${account.id}',
          child: AccountAvatar(
            name: account.name,
            icon: accountIconOrNull(account),
          ),
        ),
        title: account.name,
        subtitle: account.type.title(context),
        onTap: () => RouteUtils.pushRoute(
          AccountDetailsPage(
            account: account,
            accountIconHeroTag: 'dashboard-page__account-icon-${account.id}',
            dateRangeService: dateRangeService,
          ),
        ),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StreamBuilder(
              initialData: 0.0,
              stream: AccountService.instance.getAccountMoney(account: account),
              builder: (context, snapshot) {
                final amount = snapshot.data ?? 0.0;

                return CurrencyDisplayer(
                  amountToConvert: amount,
                  currency: account.currency,
                  compactView: amount >= 10000000,
                  integerStyle: Theme.of(context).textTheme.titleSmall!
                      .copyWith(fontFeatures: tabularFigures),
                );
              },
            ),
            StreamBuilder(
              initialData: 0.0,
              stream: AccountService.instance.getAccountsBalanceRelativeChange(
                accounts: [account],
                startDate: dateRangeService.startDate,
                endDate: dateRangeService.endDate,
                convertToPreferredCurrency: false,
              ),
              builder: (context, snapshot) {
                return TrendingValue(
                  percentage: snapshot.data ?? 0,
                  decimalDigits: 0,
                  fontSize: 12,
                  padding: EdgeInsets.zero,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The supported icon of [account], or null when it has none (the default
/// placeholder does not count).
SupportedIcon? accountIconOrNull(Account account) {
  final icon = SupportedIconService.instance.getIconByID(account.iconId);

  return icon.id == SupportedIconService.instance.defaultSupportedIcon.id
      ? null
      : icon;
}

SupportedIcon? _sharedIconOrNull(List<Account> accounts) {
  final icon = sharedAccountIcon(accounts);

  return icon == null ||
          icon.id == SupportedIconService.instance.defaultSupportedIcon.id
      ? null
      : icon;
}

/// Soft circle with the account icon, or its initial when it has no icon.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.name,
    this.icon,
    this.fallbackIcon,
    this.size = 40,
  });

  final String name;
  final SupportedIcon? icon;

  /// Shown instead of the initial when [icon] is null (account groups).
  final IconData? fallbackIcon;
  final double size;

  String get _initial {
    final trimmed = name.trim();

    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconSize = size * 0.55;

    final Widget content;
    if (icon != null) {
      content = icon!.display(
        size: iconSize,
        color: icon!.isBrandLogo ? null : scheme.primary,
      );
    } else if (fallbackIcon != null) {
      content = Icon(fallbackIcon, size: iconSize, color: scheme.primary);
    } else {
      content = Text(
        _initial,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: scheme.primary),
      );
    }

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BrandColors.of(context).soft,
          shape: BoxShape.circle,
        ),
        child: content,
      ),
    );
  }
}

/// One row of the accounts card.
class AccountRowTile extends StatelessWidget {
  const AccountRowTile({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// An expandable row that aggregates all the accounts of a group.
class _AccountGroupRow extends StatefulWidget {
  const _AccountGroupRow({
    required this.groupName,
    required this.accounts,
    required this.dateRangeService,
  });

  final String groupName;
  final List<Account> accounts;
  final DatePeriodState dateRangeService;

  @override
  State<_AccountGroupRow> createState() => _AccountGroupRowState();
}

class _AccountGroupRowState extends State<_AccountGroupRow> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    // Only a group whose accounts all share one currency can be summed as it
    // is; anything else has to go through the user preferred currency.
    final currencies = widget.accounts.map((a) => a.currency.code).toSet();
    final sharedCurrency = currencies.length == 1
        ? widget.accounts.first.currency
        : null;

    return ExpansionTile(
      key: ValueKey('dashboard-page__account-group-${widget.groupName}'),
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.only(left: 16),
      onExpansionChanged: (value) => setState(() => _isExpanded = value),
      leading: AccountAvatar(
        name: widget.groupName,
        icon: _sharedIconOrNull(widget.accounts),
        fallbackIcon: Icons.workspaces_rounded,
      ),
      // The expand affordance lives next to the name so the balance stays the
      // rightmost element, aligned with the standalone account rows.
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.groupName,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: _isExpanded ? 0.5 : 0,
            duration: BrandMotion.of(context).state,
            child: Icon(
              Icons.expand_more,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: Text(t.account.group.accounts_count(n: widget.accounts.length)),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StreamBuilder(
            initialData: 0.0,
            stream: AccountService.instance.getAccountsMoney(
              accountIds: widget.accounts.map((a) => a.id),
              convertToPreferredCurrency: sharedCurrency == null,
            ),
            builder: (context, snapshot) {
              final amount = snapshot.data ?? 0.0;

              return CurrencyDisplayer(
                amountToConvert: amount,
                currency: sharedCurrency,
                compactView: amount >= 10000000,
                integerStyle: Theme.of(
                  context,
                ).textTheme.titleSmall!.copyWith(fontFeatures: tabularFigures),
              );
            },
          ),
          StreamBuilder(
            initialData: 0.0,
            stream: AccountService.instance.getAccountsBalanceRelativeChange(
              accounts: widget.accounts,
              startDate: widget.dateRangeService.startDate,
              endDate: widget.dateRangeService.endDate,
              convertToPreferredCurrency: sharedCurrency == null,
            ),
            builder: (context, snapshot) {
              return TrendingValue(
                percentage: snapshot.data ?? 0,
                decimalDigits: 0,
                fontSize: 12,
                padding: EdgeInsets.zero,
              );
            },
          ),
        ],
      ),
      children: [
        for (final account in widget.accounts)
          _AccountRow(
            account: account,
            dateRangeService: widget.dateRangeService,
          ),
      ],
    );
  }
}

class _AccountRowSkeleton extends StatelessWidget {
  const _AccountRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer.zone(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            const Bone.circle(size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.text(width: 120),
                  const SizedBox(height: 4),
                  Bone.text(width: 70),
                ],
              ),
            ),
            Bone.text(width: 60),
          ],
        ),
      ),
    );
  }
}
