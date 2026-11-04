import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_key_store.dart';
import 'package:monekin/features_ia/google/backup_crypto.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/backup_password_sheets.dart';
import 'package:monekin/core/presentation/helpers/snackbar.dart';
import 'package:monekin/features_ia/google/backup_state_store.dart';
import 'package:monekin/features_ia/google/google_account_gateway.dart';
import 'package:monekin/features_ia/google/google_backup_page.dart';
import 'package:monekin/features_ia/google/google_backup_service.dart';
import 'package:monekin/features_ia/google/restore_flow.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import 'drive_backup_service_test.dart' show FakeAccount, FakeDrive;

Widget _app(Widget home) => TranslationProvider(child: MaterialApp(home: home));

/// Same, with a messenger where MonekinSnackbar can show.
Widget _appWithSnackbars(Widget home) => TranslationProvider(
  child: MaterialApp(home: SnackbarScope(child: home)),
);

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
      expect(
        find.text('At least 12 characters, or 4 words. A long phrase is best.'),
        findsOneWidget,
      );
    });

    testWidgets('needs 12 characters or 4 words, and a matching confirmation', (
      tester,
    ) async {
      await open(tester);
      final fields = find.byType(TextField);

      for (final tooShort in [
        'short',
        'eleven char',
        'a b c d',
        'one two six',
      ]) {
        await tester.enterText(fields.at(0), tooShort);
        await tester.enterText(fields.at(1), tooShort);
        await tester.pump();
        expect(
          tester.widget<FilledButton>(saveButton()).onPressed,
          isNull,
          reason: tooShort,
        );
      }

      await tester.enterText(fields.at(0), 'sol luna mar rio');
      await tester.enterText(fields.at(1), 'sol luna mar rio');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(saveButton()).onPressed,
        isNotNull,
        reason: 'four words',
      );

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

  group('v2 copy without encryption', () {
    testWidgets(
      'shows the notice before restoring and restores without a key',
      (tester) async {
        final plain = (await tester.runAsync(
          () => buildBackupPackage(
            database: Uint8List.fromList([1, 2, 3]),
            documentsDir: Directory.systemTemp.path,
            schemaVersion: 15,
            date: DateTime(2026, 11, 4),
          ),
        ))!;
        final drive = FakeDrive();
        await drive.upload('finanzas-20261104-083005.zip', plain);
        final received = <BackupKeyResolver?>[];
        final service = DriveBackupService(
          account: FakeAccount(email: 'a@b.com', drive: drive),
          state: MemoryBackupStateStore(),
          keyStore: MemoryBackupKeyStore(),
          restoreDatabase: (bytes, resolver) async => received.add(resolver),
        );

        await tester.pumpWidget(_app(GoogleBackupPage(service: service)));
        await _settle(tester);

        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SimpleDialogOption));
        await tester.pumpAndSettle();

        expect(find.text('Backup without encryption'), findsOneWidget);
        expect(find.textContaining('is not encrypted'), findsOneWidget);
        expect(received, isEmpty);

        await tester.tap(find.byType(TextButton).last);
        await tester.pumpAndSettle();

        expect(received, [isNull]);
        expect(find.text('Backup restored'), findsOneWidget);
      },
    );
  });

  group('current password sheet', () {
    Future<void> open(
      WidgetTester tester,
      Future<bool> Function(String) verify,
      void Function(String?) done,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => done(
                  await showCurrentPasswordSheet(context, verify: verify),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('stays open with an error after a wrong password', (
      tester,
    ) async {
      final asked = <String>[];
      var closedWith = 'still open';
      await open(tester, (password) async {
        asked.add(password);
        return password == 'the right one';
      }, (value) => closedWith = '$value');

      expect(find.text('Current password'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'the wrong one');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(asked, ['the wrong one']);
      expect(find.text('That password is not right. Try again.'), findsOne);
      expect(closedWith, 'still open');

      await tester.enterText(find.byType(TextField), 'the right one');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(asked, ['the wrong one', 'the right one']);
      expect(closedWith, 'the right one');
    });

    testWidgets('dismissing it returns nothing', (tester) async {
      var closedWith = 'still open';
      await open(tester, (_) async => true, (value) => closedWith = '$value');

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(closedWith, 'null');
    });
  });

  group('page', () {
    late FakeDrive drive;
    late MemoryBackupKeyStore keys;
    late DriveBackupService service;
    late BackupKey key;

    setUp(() async {
      key = (await createBackupKey(
        'a long enough password',
        params: const KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1),
      ));
      drive = FakeDrive();
      keys = MemoryBackupKeyStore();
      await keys.save(key);
      service = DriveBackupService(
        account: FakeAccount(email: 'a@b.com', drive: drive),
        state: MemoryBackupStateStore(),
        keyStore: keys,
        restoreDatabase: (bytes, resolver) async {},
      );
    });

    Future<void> openPage(WidgetTester tester) async {
      await tester.pumpWidget(
        _appWithSnackbars(GoogleBackupPage(service: service)),
      );
      await _settle(tester);
    }

    Future<void> tapTile(WidgetTester tester, String title) async {
      final tile = find.text(title);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    testWidgets('forgetting the password asks first and clears the key', (
      tester,
    ) async {
      await openPage(tester);

      await tapTile(tester, 'Forget the password on this phone');
      expect(find.text('Forget the backup password?'), findsOneWidget);

      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(await keys.load(), isNotNull, reason: 'cancelled');

      await tapTile(tester, 'Forget the password on this phone');
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(await keys.load(), isNull);
      expect(find.text('Forget the password on this phone'), findsNothing);
    });

    testWidgets('there is nothing to forget without a password', (
      tester,
    ) async {
      await keys.clear();

      await openPage(tester);

      expect(find.text('Forget the password on this phone'), findsNothing);
    });

    testWidgets('changing the password asks for the current one first', (
      tester,
    ) async {
      await openPage(tester);

      await tapTile(tester, 'Change backup password');

      expect(find.text('Current password'), findsOneWidget);
      expect(find.text('Create a backup password'), findsNothing);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect((await keys.load())!.key, key.key, reason: 'nothing changed');
    });

    testWidgets('deleting unencrypted copies keeps the encrypted ones', (
      tester,
    ) async {
      final sealed = (await tester.runAsync(
        () => encryptBackupBytes(Uint8List.fromList([5, 5]), key),
      ))!;
      final old = await drive.upload(
        'finanzas-20260101-000000.zip',
        Uint8List.fromList([1, 2, 3]),
      );
      final kept = await drive.upload('finanzas-20261104-083005.fia', sealed);
      await openPage(tester);

      await tapTile(tester, 'Delete unencrypted copies');
      expect(find.text('Delete the unencrypted copies?'), findsOneWidget);
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(drive.deletedIds, [old.id]);
      expect(drive.meta.keys, [kept.id]);
    });

    testWidgets(
      'declining the notice of an unencrypted copy restores nothing',
      (tester) async {
        final received = <BackupKeyResolver?>[];
        service = DriveBackupService(
          account: FakeAccount(email: 'a@b.com', drive: drive),
          state: MemoryBackupStateStore(),
          keyStore: keys,
          restoreDatabase: (bytes, resolver) async => received.add(resolver),
        );
        await drive.upload('finanzas-20260101-000000.zip', Uint8List(8));
        await openPage(tester);

        await tapTile(tester, 'Restore');
        await tester.tap(find.byType(SimpleDialogOption));
        await tester.pumpAndSettle();
        expect(find.text('Backup without encryption'), findsOneWidget);
        await tester.tap(find.byType(TextButton).first);
        await tester.pumpAndSettle();

        expect(received, isEmpty);
        expect(find.text('Backup restored'), findsNothing);
      },
    );
  });
  group('runRestoreAttempts', () {
    InvalidBackupException invalid(InvalidBackupReason reason) =>
        InvalidBackupException(reason);

    Future<bool?> run(
      WidgetTester tester,
      Future<void> Function(String? password) attempt,
      Future<void> Function() interact,
    ) async {
      bool? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await runRestoreAttempts(context, attempt),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await interact();
      return result;
    }

    testWidgets('asks again after a wrong password, then restores', (
      tester,
    ) async {
      final passwords = <String?>[];

      final result = await run(
        tester,
        (password) async {
          passwords.add(password);
          if (password == null) {
            throw invalid(InvalidBackupReason.passwordRequired);
          }
          if (password != 'right one') {
            throw invalid(InvalidBackupReason.wrongPassword);
          }
        },
        () async {
          expect(
            find.text('That password is not right. Try again.'),
            findsNothing,
          );
          await tester.enterText(find.byType(TextField), 'wrong one');
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
          await tester.pumpAndSettle();

          expect(
            find.text('That password is not right. Try again.'),
            findsOneWidget,
          );
          await tester.enterText(find.byType(TextField), 'right one');
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
          await tester.pumpAndSettle();
        },
      );

      expect(passwords, [null, 'wrong one', 'right one']);
      expect(result, isTrue);
    });

    testWidgets('dismissing the password sheet restores nothing', (
      tester,
    ) async {
      final passwords = <String?>[];

      final result = await run(
        tester,
        (password) async {
          passwords.add(password);
          throw invalid(InvalidBackupReason.passwordRequired);
        },
        () async {
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        },
      );

      expect(passwords, [null]);
      expect(result, isFalse);
    });
  });
}
