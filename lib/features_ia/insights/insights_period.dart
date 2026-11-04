// Period choices shared by the insights pages (T002).
import 'package:flutter/material.dart';
import 'package:monekin/core/presentation/widgets/expanding_segmented_tabs.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

enum InsightsPeriod { current, previous, custom }

/// [start, end) of the chosen period. [custom] is only used for [InsightsPeriod.custom].
({DateTime start, DateTime end}) insightsRangeOf(
  InsightsPeriod period, {
  DateTimeRange? custom,
}) {
  final now = DateTime.now();
  if (period == InsightsPeriod.previous) {
    return (
      start: DateTime(now.year, now.month - 1),
      end: DateTime(now.year, now.month),
    );
  }
  if (period == InsightsPeriod.custom && custom != null) {
    return (
      start: custom.start,
      end: DateTime(custom.end.year, custom.end.month, custom.end.day + 1),
    );
  }
  return (
    start: DateTime(now.year, now.month),
    end: DateTime(now.year, now.month + 1),
  );
}

/// Asks for a range of days up to today. Null when the user cancels.
Future<DateTimeRange?> pickInsightsRange(
  BuildContext context,
  DateTimeRange? initial,
) {
  final now = DateTime.now();
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(now.year - 10),
    lastDate: now,
    initialDateRange: initial,
  );
}

class InsightsPeriodTabs extends StatelessWidget {
  const InsightsPeriodTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final InsightsPeriod selected;
  final ValueChanged<InsightsPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return ExpandingSegmentedTabs<InsightsPeriod>(
      items: [
        SegmentedTabItem(
          value: InsightsPeriod.current,
          icon: Icons.calendar_today_outlined,
          label: t.ia_insights.period.current,
        ),
        SegmentedTabItem(
          value: InsightsPeriod.previous,
          icon: Icons.history_outlined,
          label: t.ia_insights.period.previous,
        ),
        SegmentedTabItem(
          value: InsightsPeriod.custom,
          icon: Icons.date_range_outlined,
          label: t.ia_insights.period.custom,
        ),
      ],
      selected: selected,
      onSelected: onSelected,
    );
  }
}
