// What the inbox shows for an item: icon, source name and a title that is never a file name.
import 'package:flutter/material.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/notifications/bank_apps.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

IconData inboxSourceIcon(InboxSource source) => switch (source) {
  InboxSource.receipt => Icons.receipt_long_outlined,
  InboxSource.statement => Icons.description_outlined,
  InboxSource.notification => Icons.notifications_outlined,
};

String inboxSourceLabel(Translations t, InboxSource source) => switch (source) {
  InboxSource.receipt => t.ia_inbox.source_receipt,
  InboxSource.statement => t.ia_inbox.source_statement,
  InboxSource.notification => t.ia_inbox.source_notification,
};

/// Merchant of a receipt, label of a statement, bank app of a notice. The
/// stored `sourceRef` of a receipt is the file name, so it is not used there.
String inboxItemTitle(Translations t, InboxItem item) {
  final label = inboxSourceLabel(t, item.source);

  switch (item.source) {
    case InboxSource.receipt:
      final merchant = item.proposals.firstOrNull?.title.trim() ?? '';
      return merchant.isEmpty ? label : merchant;
    case InboxSource.statement:
      return item.sourceRef.isEmpty ? label : item.sourceRef;
    case InboxSource.notification:
      return bankAppFor(item.sourceRef)?.name ?? label;
  }
}

/// Income minus expenses of the rows, in the currency of their account.
double inboxItemNet(InboxItem item) {
  var net = 0.0;
  for (final p in item.proposals) {
    net += p.type == TransactionType.income ? p.amount : -p.amount;
  }
  return net;
}
