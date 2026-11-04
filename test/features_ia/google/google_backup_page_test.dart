import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_key_store.dart';
import 'package:monekin/features_ia/google/backup_password_sheets.dart';
import 'package:monekin/features_ia/google/backup_state_store.dart';
import 'package:monekin/features_ia/google/google_account_gateway.dart';
import 'package:monekin/features_ia/google/google_backup_page.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

Widget _app(Widget home) => TranslationProvider(child: MaterialApp(home: home));

/// Lets the page's async work (real I/O) finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'BUG-06: without a Google client id the page explains it, with no exception',
    (tester) async {
      final service = DriveBackupService(
        account: RealGoogleAccountGateway(
          serverClientId: '',
          requiresClientId: true,
        ),
        state: MemoryBackupStateStore(),
        keyStore: MemoryBackupKeyStore(),
      );

      await tester.pumpWidget(_app(GoogleBackupPage(service: service)));
      await _settle(tester);

      expect(
        find.text('Google is not set up in this version of the app'),
        findsOneWidget,
      );
      expect(find.text('Local backups still work: use Export data.'), findsOne);
      expect(find.text('Sign in with Google'), findsNothing);
      expect(find.textContaining('serverClientId'), findsNothing);
      expect(find.textContaining('GoogleSignInException'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  group('create password sheet', () {
    Future<String?> open(WidgetTester tester, {bool change = false}) async {
      String? result;
      var done = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCreateBackupPasswordSheet(
                    context,
                    change: change,
                  );
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(done, isFalse);
      return result;
    }

    Finder saveButton() => find.widgetWithText(FilledButton, 'Save password');

    testWidgets('warns that a forgotten password cannot be recovered', (
      tester,
    ) async {
      await open(tester);

      expect(
        find.text(
          'If you forget it, these backups cannot be restored. Nobody can recover it.',
        ),
        findsOneWidget,
      );
      expect(find.text('At least 10 characters'), findsOneWidget);
    });

    testWidgets('needs 10 characters and a matching confirmation', (
      tester,
    ) async {
      await open(tester);
      final fields = find.byType(TextField);

      await tester.enterText(fields.at(0), 'short');
      await tester.enterText(fields.at(1), 'short');
      await tester.pump();
      expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);

      await tester.enterText(fields.at(0), 'long enough password');
      await tester.enterText(fields.at(1), 'long enough passwor');
      await tester.pump();
      expect(find.text('The passwords do not match'), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);

      await tester.enterText(fields.at(1), 'long enough password');
      await tester.pump();
      expect(find.text('The passwords do not match'), findsNothing);
      expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
    });

    testWidgets('returns the password, and the change variant says old copies '
        'keep the old one', (tester) async {
      String? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result =
                    await showCreateBackupPasswordSheet(context, change: true),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Backups you already made will still ask for the previous password.',
        ),
        findsOneWidget,
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'long enough password');
      await tester.enterText(fields.at(1), 'long enough password');
      await tester.pump();
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(result, 'long enough password');
    });
  });

  group('restore password sheet', () {
    testWidgets('shows the error after a wrong password', (tester) async {
      await tester.pumpWidget(
        _app(const Scaffold(body: RestorePasswordSheet(wrongBefore: true))),
      );

      expect(find.text('That password is not right. Try again.'), findsOne);
    });

    testWidgets('returns what was typed', (tester) async {
      String? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showRestorePasswordSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'the old password');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();

      expect(result, 'the old password');
    });
  });
}
