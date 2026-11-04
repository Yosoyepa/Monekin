import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:monekin/app/layout/widgets/inbox_pending.dart';
import 'package:monekin/app/layout/widgets/scan_receipt_button.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/routes/destinations.dart';
import 'package:monekin/core/utils/unique_app_widgets_keys.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

const _barHeight = 72.0;
const _scanSlotWidth = 64.0;

/// Bottom navigation bar used in mobile layout: the destinations on both sides
/// of the central "Scan receipt" button.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.selectedDestination});

  final AppMenuDestinationsID selectedDestination;

  @override
  Widget build(BuildContext context) {
    final menuItems = getDestinations(context);
    final scanAt = (menuItems.length / 2).ceil();

    // Each side gets half of the bar, so the scan button stays centered.
    Widget side(List<MainMenuDestination> items) {
      return Expanded(
        child: Row(
          children: [
            for (final item in items)
              // Longer labels get more room, so none is cut at 360 dp.
              Expanded(
                flex: math.max(item.label.length, 7),
                child: _BarItem(
                  destination: item,
                  selected: item.id == selectedDestination,
                ),
              ),
          ],
        ),
      );
    }

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: Row(
            children: [
              side(menuItems.sublist(0, scanAt)),
              const SizedBox(
                width: _scanSlotWidth,
                child: Center(child: ScanReceiptButton()),
              ),
              side(menuItems.sublist(scanAt)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({required this.destination, required this.selected});

  final MainMenuDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = BrandMotion.of(context);
    final color = selected
        ? scheme.primary
        : BrandColors.of(context).textSecondary;

    Widget item(int pending) {
      final pendingLabel = pending > 0
          ? Translations.of(context).brand_app.nav_inbox_pending(n: pending)
          : null;

      return Semantics(
        button: true,
        selected: selected,
        label: pendingLabel ?? destination.label,
        excludeSemantics: true,
        onTap: () => tabsPageKey.currentState?.changePage(destination.id),
        child: InkWell(
          onTap: () => tabsPageKey.currentState?.changePage(destination.id),
          borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: motion.state,
                curve: motion.enter,
                width: 56,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: color, size: 24),
                  child: PendingBadge(
                    count: pending,
                    child: Icon(
                      selected
                          ? destination.selectedIcon ?? destination.icon
                          : destination.icon,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (destination.id != AppMenuDestinationsID.inbox) return item(0);

    return InboxPendingBuilder(builder: (context, count) => item(count));
  }
}
