import 'package:flutter/material.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/presentation/responsive/breakpoints.dart';

/// Arrangement of the dashboard sections, with their staggered entrance. The
/// sections come in as widgets so the page fills them with live data.
class DashboardLayout extends StatelessWidget {
  const DashboardLayout({
    super.key,
    required this.header,
    required this.balance,
    required this.expenseCard,
    required this.incomeCard,
    required this.accounts,
    required this.health,
    required this.categories,
    this.footer,
  });

  final Widget header;
  final Widget balance;
  final Widget expenseCard;
  final Widget incomeCard;
  final Widget accounts;
  final Widget health;
  final Widget categories;
  final Widget? footer;

  static const _margin = BrandTokens.pageMargin;
  static const _gap = SizedBox(height: 16);

  @override
  Widget build(BuildContext context) {
    final point = BreakPoint.of(context);
    final isWide = point.isLargerOrEqualTo(BreakpointID.md);
    final isVeryWide = point.isLargerOrEqualTo(BreakpointID.xxl);

    Widget stagger(int index, Widget child) =>
        StaggeredEntrance(index: index, child: child);

    final flows = stagger(
      2,
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: expenseCard),
            const SizedBox(width: 12),
            Expanded(child: incomeCard),
          ],
        ),
      ),
    );
    final accountsSection = stagger(3, accounts);
    final healthSection = stagger(4, health);
    final categoriesSection = stagger(5, categories);

    // Wide screens put the balance in a flat card, like the other cards.
    final balanceSection = stagger(
      1,
      isWide
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: _margin),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: balance,
                ),
              ),
            )
          : balance,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stagger(
          0,
          Padding(
            padding: const EdgeInsets.fromLTRB(_margin, 8, _margin, 0),
            child: header,
          ),
        ),
        const SizedBox(height: 16),
        balanceSection,
        _gap,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _margin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isVeryWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(children: [flows, _gap, accountsSection]),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [healthSection, _gap, categoriesSection],
                      ),
                    ),
                  ],
                )
              else ...[
                flows,
                _gap,
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: accountsSection),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [healthSection, _gap, categoriesSection],
                        ),
                      ),
                    ],
                  )
                else ...[
                  accountsSection,
                  _gap,
                  healthSection,
                  _gap,
                  categoriesSection,
                ],
              ],
              ?footer,
            ],
          ),
        ),
      ],
    );
  }
}
