// Receipt capture entry point (T002). Owner: w-recibos.
// Called by the camera button of the home screen: camera -> AI proposal -> inbox review.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/privacy/picker_copy.dart';
import 'package:monekin/features_ia/inbox/inbox_navigation.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';
import 'package:monekin/features_ia/receipts/receipt_reading_page.dart';
import 'package:monekin/features_ia/receipts/receipt_store.dart';
import 'package:monekin/features_ia/settings/ai_settings_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

const _maxSide = 1600.0;
const _quality = 80;

/// Camera -> AI -> inbox. Without a configured AI it offers to open the AI settings instead.
Future<void> startReceiptCapture(BuildContext context) async {
  final t = Translations.of(context).ia_receipts;
  if (!await AiService.instance.isConfigured()) {
    if (!context.mounted) return;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.not_configured_title),
        content: Text(t.not_configured_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.open_settings),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await RouteUtils.pushRoute(const AiSettingsPage());
    }
    return;
  }

  final picker = ImagePicker();
  var photos = <XFile>[];
  try {
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: _quality,
      requestFullMetadata: false,
    );
    if (shot != null) photos = [shot];
  } catch (_) {
    // No camera (emulator, desktop) or permission denied: the gallery option below still works.
  }

  if (photos.isEmpty) {
    if (!context.mounted) return;
    final fromGallery = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(t.pick_from_gallery),
          onTap: () => Navigator.pop(context, true),
        ),
      ),
    );
    if (fromGallery != true) return;
    photos = await picker.pickMultiImage(
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: _quality,
    );
    if (photos.isEmpty) return;
  }

  final saved = <SavedReceiptPhoto>[];
  for (final photo in photos) {
    saved.add(await saveReceiptPhoto(File(photo.path)));
    await deletePickerCopy(photo.path);
  }

  if (!context.mounted) return;
  final analyzer = ReceiptAnalyzer(
    messages: ReceiptMessages(
      defaultTitle: t.default_title,
      missingDate: t.warn_no_date,
      missingMerchant: t.warn_no_merchant,
      missingTotal: t.warn_no_total,
      aiError: (kind) => switch (kind) {
        AiErrorKind.notConfigured => t.err_not_configured,
        AiErrorKind.invalidKey => t.err_invalid_key,
        AiErrorKind.quotaExceeded => t.err_quota,
        AiErrorKind.network => t.err_network,
        AiErrorKind.timeout => t.err_timeout,
        AiErrorKind.badResponse => t.err_bad_response,
        AiErrorKind.unknown => t.err_unknown,
      },
    ),
  );
  final itemIds = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) => ReceiptReadingPage(photos: saved, analyzer: analyzer),
    ),
  );
  if (itemIds == null || itemIds.isEmpty || !context.mounted) return;

  if (itemIds.length == 1) {
    await openInboxReview(context, itemIds.single);
  } else {
    await openInbox(context);
  }
}
