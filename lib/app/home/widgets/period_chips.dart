import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/models/date-utils/date_period.dart';
import 'package:monekin/core/presentation/widgets/dates/date_period_modal.dart';
import 'package:monekin/core/presentation/widgets/dates/date_range_chips.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

const _chipHeight = 36.0;

/// Quick period chips of the dashboard: the selected one is filled with the
/// accent, the others rest on the `soft` tone. Chips wrap instead of scrolling
/// so nothing is hidden, and each one keeps a 48 dp touch area.
class PeriodChips extends StatelessWidget {
  const PeriodChips({
    super.key,
    required this.currentPeriod,
    required this.onPeriodSelected,
  });

  final DatePeriod currentPeriod;
  final ValueChanged<DatePeriod> onPeriodSelected;

  Future<void> _openCustom(BuildContext context) async {
    final period = await openDatePeriodModal(
      context,
      DatePeriodModal(initialDatePeriod: currentPeriod),
    );

    if (period != null) onPeriodSelected(period);
  }

  @override
  Widget build(BuildContext context) {
    final ranges = Translations.of(context).home.date_ranges;

    final presets = [
      DateRangePreset(label: ranges.week, period: const DatePeriod.lastDays(7)),
      DateRangePreset(
        label: ranges.month,
        period: const DatePeriod.lastDays(30),
      ),
      DateRangePreset(
        label: ranges.quarter,
        period: const DatePeriod.lastDays(90),
      ),
      DateRangePreset(
        label: ranges.half_year,
        period: const DatePeriod.lastDays(180),
      ),
      DateRangePreset(
        label: ranges.year,
        period: const DatePeriod.lastDays(365),
      ),
      DateRangePreset(label: ranges.max, period: const DatePeriod.allTime()),
    ];

    final isCustom = !presets.any((p) => p.matches(currentPeriod));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Seven 48 dp targets do not fit below ~340 dp: drop the 3M one.
        final shown = constraints.maxWidth < 340
            ? presets.where((p) => p.label != ranges.quarter)
            : presets;

        return Wrap(
          children: [
            for (final preset in shown)
              _PeriodChip(
                label: preset.label,
                selected: preset.matches(currentPeriod),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPeriodSelected(preset.period);
                },
              ),
            _PeriodChip(
              label: ranges.custom,
              icon: Icons.calendar_month_rounded,
              selected: isCustom,
              onTap: () {
                HapticFeedback.selectionClick();
                _openCustom(context);
              },
            ),
          ],
        );
      },
    );
  }
}

class _PeriodChip extends StatefulWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// When set, the chip shows only the icon; the label is its tooltip.
  final IconData? icon;

  @override
  State<_PeriodChip> createState() => _PeriodChipState();
}

class _PeriodChipState extends State<_PeriodChip> {
  double _scale = 1;

  @override
  void didUpdateWidget(_PeriodChip oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A short squash and a bounce back when the chip becomes the selected one.
    if (!oldWidget.selected &&
        widget.selected &&
        !BrandMotion.of(context).reduce) {
      _scale = 0.92;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _scale = 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = BrandMotion.of(context);
    final fill = widget.selected
        ? scheme.primary
        : BrandColors.of(context).soft;
    final foreground = widget.selected ? scheme.onPrimary : scheme.onSurface;

    final content = widget.icon != null
        ? Icon(widget.icon, size: 18, color: foreground)
        : Text(
            widget.label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: foreground),
          );

    final pill = AnimatedContainer(
      duration: motion.state,
      curve: motion.enter,
      height: _chipHeight,
      constraints: const BoxConstraints(minWidth: _chipHeight),
      padding: EdgeInsets.symmetric(horizontal: widget.icon != null ? 9 : 10),
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      child: Center(widthFactor: 1, child: content),
    );

    final target = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: BrandTokens.buttonHeight,
          minWidth: BrandTokens.buttonHeight,
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: AnimatedScale(
            scale: _scale,
            duration: motion.tap,
            curve: motion.bounce,
            child: PressScale(child: pill),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: widget.icon != null
          ? Tooltip(message: widget.label, child: target)
          : target,
    );
  }
}
