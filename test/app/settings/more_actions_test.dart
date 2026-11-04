import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/settings/more_actions.page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../ui_test_utils.dart';

void main() {
  setUpAll(() async {
    await loadUiFonts();
    await LocaleSettings.setLocale(AppLocale.es);
  });

  for (final width in [360.0, 1400.0]) {
    testWidgets('More does not list the inbox, it is already a tab (width '
        '${width.toInt()})', (tester) async {
      await useSurface(tester, width, 900);
      await tester.pumpWidget(uiApp(const MoreActionsPage()));
      await tester.pump(const Duration(milliseconds: 500));

      final t = Translations.of(tester.element(find.byType(MoreActionsPage)));

      expect(find.text(t.ia_inbox.title), findsNothing);
      // Other actions that are not tabs are still there.
      expect(find.text(t.ia_insights.title), findsOneWidget);
      expect(find.text(t.goals.title), findsOneWidget);
    });
  }
}
