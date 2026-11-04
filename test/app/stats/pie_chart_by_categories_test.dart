// BUG-05 (docs/e2e/E002_report.md): repainting the categories pie chart with other data raised a RangeError in fl_chart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/stats/widgets/movements_distribution/pie_chart_by_categories.dart';
import 'package:monekin/app/stats/widgets/movements_distribution/tr_distribution_chart_item.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/date-utils/date_period_state.dart';
import 'package:monekin/core/presentation/app_colors.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

Category _category(String id) => Category(
  id: id,
  name: id,
  iconId: 'wallet',
  displayOrder: 0,
  color: '4385be',
  type: CategoryType.E,
);

TrDistributionChartItem<Category> _item(String id, double value) =>
    TrDistributionChartItem(
      category: _category(id),
      transactions: [],
      value: value,
    );

void main() {
  testWidgets('new data with other sections repaints without a RangeError', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    final controller =
        StreamController<List<TrDistributionChartItem<Category>>>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: scheme,
            extensions: [AppColors.fromColorScheme(scheme)],
          ),
          home: Scaffold(
            body: PieChartByCategories(
              datePeriodState: const DatePeriodState(),
              debugItems: controller.stream,
            ),
          ),
        ),
      ),
    );

    // Three sections, one of them too small to show its badge.
    controller.add([_item('a', 70), _item('b', 28), _item('c', 2)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Recategorized: other categories and fewer sections.
    controller.add([_item('b', 60), _item('d', 40)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    // And back to more sections, again with a small one first.
    controller.add([
      _item('e', 1),
      _item('a', 50),
      _item('b', 30),
      _item('f', 19),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });
}
