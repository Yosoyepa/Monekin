// Attachments of a transaction, shown in its details page (T002). Owner: w-inbox.
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/presentation/widgets/card_with_header.dart';
import 'package:monekin/features_ia/inbox/attachment_thumbnail.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class TransactionAttachmentsSection extends StatelessWidget {
  const TransactionAttachmentsSection({
    super.key,
    required this.transactionId,
    this.db,
  });

  final String transactionId;

  /// Only for tests; the app uses [AppDB.instance].
  final AppDB? db;

  @override
  Widget build(BuildContext context) {
    final database = db ?? AppDB.instance;

    return StreamBuilder<List<TransactionAttachmentInDB>>(
      stream:
          (database.select(database.transactionAttachments)
                ..where((a) => a.transactionID.equals(transactionId))
                ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
              .watch(),
      builder: (context, snapshot) {
        final attachments = snapshot.data ?? const [];

        if (attachments.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CardWithHeader(
            title: t.ia_inbox.attachments_title,
            bodyPadding: const EdgeInsets.all(12),
            body: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in attachments)
                  AttachmentThumbnail(path: a.filePath),
              ],
            ),
          ),
        );
      },
    );
  }
}
