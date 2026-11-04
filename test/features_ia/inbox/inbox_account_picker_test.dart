import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/features_ia/inbox/inbox_account_picker.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// Reads and writes the accounts of a test database the way [AccountService]
/// does: the flag is cleared with `replace` on the account row.
class DbAccountSource implements InboxAccountSource {
  DbAccountSource(this.db);

  final AppDB db;
  int loads = 0;

  @override
  Future<List<Account>> accounts() async {
    loads++;
    final rows = await db.select(db.accounts).get();
    if (rows.isEmpty) return [];
    final currency = await db.select(db.currencies).getSingle();

    return [for (final row in rows) Account.fromDB(row, currency)];
  }

  @override
  Future<Account?> clearSavingFlag(Account account) async {
    await db.update(db.accounts).replace(account.copyWith(isSaving: false));

    final row = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(account.id))).getSingle();
    final currency = await db.select(db.currencies).getSingle();

    return Account.fromDB(row, currency);
  }
}

Future<AppDB> seededDb() async {
  final db = AppDB.forTesting(NativeDatabase.memory());

  await db
      .into(db.currencies)
      .insert(
        const CurrencyInDB(
          code: 'COP',
          symbol: r'$',
          name: 'Peso',
          decimalPlaces: 2,
          isDefault: true,
          type: 0,
        ),
      );

  for (final (id, name, saving) in [
    ('acc-normal', 'Bancolombia', false),
    ('acc-saving', 'Nequi', true),
  ]) {
    await db
        .into(db.accounts)
        .insert(
          AccountInDB(
            id: id,
            name: name,
            iniValue: 0,
            date: DateTime(2020),
            type: AccountType.money,
            isSaving: saving,
            trackingMode: AccountTrackingMode.transactions,
            iconId: 'wallet',
            displayOrder: 0,
            currencyId: 'COP',
          ),
        );
  }

  return db;
}

Future<bool> savingFlagOf(AppDB db, String id) async {
  final row = await (db.select(
    db.accounts,
  )..where((a) => a.id.equals(id))).getSingle();

  return row.isSaving;
}

Widget harness(Widget page) => TranslationProvider(
  child: MaterialApp(home: Scaffold(body: page)),
);

void main() {
  testWidgets('a normal account is chosen with one tap and no dialog', (
    tester,
  ) async {
    final db = await seededDb();
    addTearDown(db.close);
    Account? chosen;

    await tester.pumpWidget(
      harness(
        InboxAccountPicker(
          source: DbAccountSource(db),
          onChosen: (account) => chosen = account,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('inbox-account-acc-normal')));
    await tester.pumpAndSettle();

    expect(chosen?.id, 'acc-normal');
    expect(find.byKey(const Key('inbox-saving-unmark')), findsNothing);
  });

  testWidgets(
    'a savings account shows its note; cancel changes nothing and confirm unmarks it in the database',
    (tester) async {
      final db = await seededDb();
      addTearDown(db.close);
      Account? chosen;

      await tester.pumpWidget(
        harness(
          InboxAccountPicker(
            source: DbAccountSource(db),
            onChosen: (account) => chosen = account,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('inbox-account-acc-saving')),
          matching: find.text('Piggy bank: transfers only'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('inbox-account-acc-normal')),
          matching: find.text('Piggy bank: transfers only'),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('inbox-account-acc-saving')));
      await tester.pumpAndSettle();
      expect(find.textContaining('is marked as a piggy bank'), findsOneWidget);

      await tester.tap(find.byKey(const Key('inbox-saving-cancel')));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
      expect(await savingFlagOf(db, 'acc-saving'), isTrue);

      await tester.tap(find.byKey(const Key('inbox-account-acc-saving')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inbox-saving-unmark')));
      await tester.pumpAndSettle();

      expect(await savingFlagOf(db, 'acc-saving'), isFalse);
      expect(chosen?.id, 'acc-saving');
      expect(chosen?.isSaving, isFalse);
    },
  );

  testWidgets(
    'Create account opens the account form through its seam and reloads the list after it',
    (tester) async {
      final db = await seededDb();
      addTearDown(db.close);
      final source = DbAccountSource(db);
      var opened = 0;

      await tester.pumpWidget(
        harness(
          InboxAccountPicker(
            source: source,
            onChosen: (_) {},
            onCreateAccount: (context) async {
              opened++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.loads, 1);

      await tester.tap(find.byKey(const Key('inbox-account-create')));
      await tester.pumpAndSettle();

      expect(opened, 1);
      expect(source.loads, 2);
    },
  );

  testWidgets(
    'with no accounts the picker says how to create one, without a plus sign',
    (tester) async {
      final db = AppDB.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        harness(
          InboxAccountPicker(source: DbAccountSource(db), onChosen: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You have no accounts yet. Tap “Create account”.'),
        findsOneWidget,
      );
      expect(find.textContaining('+'), findsNothing);
      expect(find.byKey(const Key('inbox-account-create')), findsOneWidget);
    },
  );
}
