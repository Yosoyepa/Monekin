// BUG-08: after a restore the app shows its own «restart» screen and keeps no screen alive
// that reads the database, which is already closed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/google/backup_package.dart';
import 'package:monekin/features_ia/google/restore_flow.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// Stands for every widget that reads the database (`UserProfileBuilder`, the sidebar...): once the
/// database is [closed], building it again fails.
class _DatabaseReader extends StatelessWidget {
  const _DatabaseReader(this.closed);

  final ValueNotifier<bool> closed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: closed,
    builder: (_, isClosed, _) {
      if (isClosed) {
        throw StateError('Null check operator used on a null value');
      }
      return const Text('profile');
    },
  );
}

class _Home extends StatelessWidget {
  const _Home(this.closed, this.restore);

  final ValueNotifier<bool> closed;
  final Future<void> Function(BuildContext context) restore;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: _DatabaseReader(closed)),
    body: Column(
      children: [
        _DatabaseReader(closed),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => restore(context),
            child: const Text('Start the restore'),
          ),
        ),
      ],
    ),
  );
}

Widget _app(
  ValueNotifier<bool> closed,
  Future<void> Function(BuildContext) go,
) => TranslationProvider(
  child: MaterialApp(
    home: _Home(closed, go),
    builder: (context, child) => child!,
  ),
);

void main() {
  late ValueNotifier<bool> closed;

  setUp(() => closed = ValueNotifier(false));

  tearDown(() => closed.dispose());

  testWidgets(
    'after a restore only the restart screen is left, with no framework errors',
    (tester) async {
      await tester.pumpWidget(
        _app(closed, (context) async {
          final restored = await runRestoreAttempts(context, (_) async {
            // The restore closes the database it was reading.
            closed.value = false;
          });
          expect(restored, isTrue);
          if (context.mounted) await showRestartRequiredPage(context);
        }),
      );
      expect(find.byType(_DatabaseReader), findsNWidgets(2));

      await tester.tap(find.text('Start the restore'));
      await tester.pumpAndSettle();

      expect(find.byType(RestartRequiredPage), findsOneWidget);
      expect(find.text('Backup restored'), findsOneWidget);
      expect(find.text('Close the app'), findsOneWidget);
      expect(find.byType(_DatabaseReader), findsNothing);
      expect(find.text('Start the restore'), findsNothing);

      // The database is closed now: nothing that is still alive may read it.
      closed.value = true;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(RestartRequiredPage), findsOneWidget);
    },
  );

  testWidgets(
    'a restore that fails after closing the database shows the failed variant',
    (tester) async {
      await tester.pumpWidget(
        _app(closed, (context) async {
          final restored = await runRestoreAttempts(context, (_) async {
            throw const RestoreNeedsRestartException('closed');
          });
          expect(restored, isFalse);
        }),
      );

      await tester.tap(find.text('Start the restore'));
      await tester.pumpAndSettle();

      expect(find.byType(RestartRequiredPage), findsOneWidget);
      expect(find.text('The restore failed'), findsOneWidget);
      expect(find.byType(_DatabaseReader), findsNothing);

      closed.value = true;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the screen cannot be popped and its button closes the app', (
    tester,
  ) async {
    var closes = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: RestartRequiredPage(closeApp: () async => closes++),
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RestartRequiredPage), findsOneWidget);

    await tester.tap(find.text('Close the app'));
    expect(closes, 1);
  });
}
