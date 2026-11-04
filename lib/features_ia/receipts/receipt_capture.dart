// Receipt capture entry point (T002). Owner: w-recibos.
// Called by the camera button of the home screen: camera -> AI proposal -> inbox review.
import 'package:flutter/material.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/core/widgets/coming_soon_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

Future<void> startReceiptCapture(BuildContext context) async {
  await RouteUtils.pushRoute(ComingSoonPage(title: Translations.of(context).ia_receipts.title));
}
