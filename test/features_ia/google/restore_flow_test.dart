// A restore that finds a background task still running (T002, round 8) says so, asks
// the user to try again and restores nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/backup/restore_lock.dart';
import 'package:monekin/core/presentation/helpers/snackbar.dart';
import 'package:monekin/features_ia/google/restore_flow.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

Widget _app(Widget body) => TranslationProvider(
  child: MaterialApp(
    home: SnackbarScope(
      child: Scaffold(body: Center(child: body)),
    ),
  ),
);

void main() {
  setUpAll(() async {
    // Spanish is a deferred library: it loads outside the fake clock of testWidgets.
    await LocaleSettings.setLocale(AppLocale.es);
  });

  for (final locale in [AppLocale.en, AppLocale.es]) {
    testWidgets(
      'a restore that finds a background task running says so and returns false (${locale.name})',
      (tester) async {
        await LocaleSettings.setLocale(locale);
        bool? restored;

        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  restored = await runRestoreAttempts(
                    context,
                    (_) async => throw const RestoreBusyException(),
                  );
                },
                child: const Text('restore'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('restore'));
        await tester.pumpAndSettle();

        expect(restored, isFalse);
        expect(find.text(t.ia_google.restore_busy), findsOneWidget);
      },
    );
  }
}
