import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/features_ia/core/dedupe/dedupe.dart';
import 'package:monekin/features_ia/inbox/drift_inbox_service.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';

/// Stand-in for `findDuplicates` of w-utils: same account, type and amount,
/// at most one day apart and one title containing the other.
List<DedupeMatch> fakeFindDuplicates(
  List<DedupeCandidate> rows,
  List<DedupeCandidate> existing,
) {
  bool same(DedupeCandidate a, DedupeCandidate b) {
    final titleA = a.title.toLowerCase().trim();
    final titleB = b.title.toLowerCase().trim();

    return a.accountId == b.accountId &&
        a.type == b.type &&
        (a.amount - b.amount).abs() < 0.005 &&
        a.date.difference(b.date).inHours.abs() <= 24 &&
        (titleA.contains(titleB) || titleB.contains(titleA));
  }

  final matches = <DedupeMatch>[];

  for (var i = 0; i < rows.length; i++) {
    final other = existing.where((e) => same(rows[i], e)).firstOrNull;
    if (other != null) {
      matches.add(
        DedupeMatch(rowIndex: i, existingId: other.id, reason: 'stored'),
      );
      continue;
    }

    for (var j = 0; j < i; j++) {
      if (same(rows[i], rows[j])) {
        matches.add(
          DedupeMatch(rowIndex: i, otherRowIndex: j, reason: 'batch'),
        );
        break;
      }
    }
  }

  return matches;
}

class InboxTestEnv {
  InboxTestEnv._(this.db, this.service);

  final AppDB db;
  final DriftInboxService service;

  static Future<InboxTestEnv> create({DuplicateFinder? finder}) async {
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

    for (final (id, name, date) in [
      ('acc-1', 'Bancolombia', DateTime(2020)),
      ('acc-2', 'Nequi', DateTime(2026, 6)),
    ]) {
      await db
          .into(db.accounts)
          .insert(
            AccountInDB(
              id: id,
              name: name,
              iniValue: 0,
              date: date,
              type: AccountType.money,
              isSaving: false,
              trackingMode: AccountTrackingMode.transactions,
              iconId: 'wallet',
              displayOrder: 0,
              currencyId: 'COP',
            ),
          );
    }

    for (final (id, name, type) in [
      ('cat-e', 'Food', CategoryType.E),
      ('cat-i', 'Salary', CategoryType.I),
    ]) {
      await db
          .into(db.categories)
          .insert(
            CategoryInDB(
              id: id,
              name: name,
              iconId: 'wallet',
              color: '4385be',
              type: type,
              displayOrder: 0,
            ),
          );
    }

    return InboxTestEnv._(
      db,
      DriftInboxService(
        db: db,
        transactions: TransactionService.forTesting(db),
        findDuplicates: finder ?? fakeFindDuplicates,
      ),
    );
  }

  Future<void> close() => db.close();

  Future<List<TransactionInDB>> transactions() => (db.select(
    db.transactions,
  )..orderBy([(t) => OrderingTerm.asc(t.date)])).get();
}

ProposedTransaction row({
  String title = 'KFC',
  double amount = 45900,
  DateTime? date,
  String? categoryId = 'cat-e',
  String? accountId = 'acc-1',
  String? notes,
}) => ProposedTransaction(
  date: date ?? DateTime(2026, 10, 20, 13, 30),
  title: title,
  amount: amount,
  categoryId: categoryId,
  accountId: accountId,
  notes: notes,
);

InboxDraft draft(
  List<ProposedTransaction> rows, {
  InboxSource source = InboxSource.receipt,
  String ref = 'recibo-01.jpg',
  List<String> attachments = const [],
}) => InboxDraft(
  source: source,
  sourceRef: ref,
  proposals: rows,
  attachmentPaths: attachments,
);
