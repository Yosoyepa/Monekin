// «Reading receipt…» screen: analyzes the photos one by one and pops with the inbox item ids. Owner: w-recibos.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';
import 'package:monekin/features_ia/receipts/receipt_store.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class ReceiptReadingPage extends StatefulWidget {
  const ReceiptReadingPage({
    super.key,
    required this.photos,
    required this.analyzer,
  });

  final List<SavedReceiptPhoto> photos;
  final ReceiptAnalyzer analyzer;

  @override
  State<ReceiptReadingPage> createState() => _ReceiptReadingPageState();
}

class _ReceiptReadingPageState extends State<ReceiptReadingPage> {
  int _current = 1;
  int _next = 0;
  final _ids = <String>[];

  /// Draft whose inbox save failed. Its photo stays on disk and [_retry] saves this same draft.
  InboxDraft? _unsaved;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    while (_next < widget.photos.length) {
      if (!mounted) return;
      final photo = widget.photos[_next];
      setState(() => _current = _next + 1);
      final draft = await widget.analyzer.analyze(
        imageBytes: photo.bytes,
        filePath: photo.path,
        fileName: photo.fileName,
      );
      if (!await _save(draft)) return;
    }
    if (mounted) Navigator.of(context).pop(_ids);
  }

  Future<bool> _save(InboxDraft draft) async {
    try {
      _ids.add(await InboxService.instance.addItem(draft));
      _next++;
      return true;
    } catch (_) {
      if (mounted) setState(() => _unsaved = draft);
      return false;
    }
  }

  Future<void> _retry() async {
    final draft = _unsaved;
    if (draft == null) return;
    setState(() => _unsaved = null);
    if (await _save(draft)) await _run();
  }

  Future<void> _discard() async {
    final t = Translations.of(context).ia_receipts;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.discard_title),
        content: Text(t.discard_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.discard_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final photo = widget.photos[_next];
    setState(() => _unsaved = null);
    deleteReceiptPhoto(photo);
    _next++;
    await _run();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_receipts;
    final total = widget.photos.length;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_unsaved != null) ...[
                  Text(
                    t.save_failed,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _retry, child: Text(t.retry)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _discard, child: Text(t.discard)),
                ] else ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    total > 1
                        ? t.reading_n(current: _current, total: total)
                        : t.reading,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
