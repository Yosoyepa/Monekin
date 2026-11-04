// Navigation into the inbox (T002). Owner: w-inbox. Receipts, statements and notifications call these.
import 'package:flutter/material.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/inbox/inbox_page.dart';
import 'package:monekin/features_ia/inbox/inbox_review_page.dart';

/// Opens the review page of one inbox item (rows editable, confirm or discard).
Future<void> openInboxReview(BuildContext context, String itemId) async {
  await RouteUtils.pushRoute(InboxReviewPage(itemId: itemId));
}

Future<void> openInbox(BuildContext context) async {
  await RouteUtils.pushRoute(const InboxPage());
}
