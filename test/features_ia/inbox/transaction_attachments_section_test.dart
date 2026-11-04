import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/features_ia/inbox/attachment_thumbnail.dart';
import 'package:monekin/features_ia/inbox/transaction_attachments_section.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

void main() {
  testWidgets(
    'shows a thumbnail per attachment and nothing when there are none',
    (tester) async {
      final db = AppDB.forTesting(NativeDatabase.memory());

      Widget app() => TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: TransactionAttachmentsSection(transactionId: 'tx-1', db: db),
          ),
        ),
      );

      await tester.runAsync(() async {
        await db.customStatement('PRAGMA foreign_keys = OFF');
        for (final name in ['a.jpg', 'b.jpg']) {
          await db
              .into(db.transactionAttachments)
              .insert(
                TransactionAttachmentInDB(
                  id: 'att-$name',
                  transactionID: 'tx-1',
                  filePath: '/nonexistent/$name',
                  createdAt: DateTime(2026, 11, 4),
                ),
              );
        }
      });

      await tester.pumpWidget(app());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      expect(find.text('Attachments'), findsOneWidget);
      expect(find.byType(AttachmentThumbnail), findsNWidgets(2));

      // Stop listening before the database is closed.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(db.close);
    },
  );
}
