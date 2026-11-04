// «Reading receipt…» screen: analyzes the photos one by one and pops with the inbox item ids. Owner: w-recibos.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/receipts/receipt_analyzer.dart';
import 'package:monekin/features_ia/receipts/receipt_store.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
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
  bool _cancelled = false;

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
      if (_cancelled || !await _save(draft)) return;
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

  /// Stops reading: the photos not saved yet are deleted and the page closes
  /// with the items already saved. An answer still on its way is ignored.
  void _cancel() {
    _cancelled = true;
    for (var i = _next; i < widget.photos.length; i++) {
      deleteReceiptPhoto(widget.photos[i]);
    }
    Navigator.of(context).pop(_ids);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_receipts;
    final total = widget.photos.length;
    final failed = _unsaved != null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: failed
              ? IaStatusView(
                  mood: ChanchiMood.worried,
                  title: t.save_failed,
                  actions: [
                    FilledButton(onPressed: _retry, child: Text(t.retry)),
                    TextButton(onPressed: _discard, child: Text(t.discard)),
                  ],
                )
              : IaStatusView(
                  mood: ChanchiMood.thinking,
                  title: total > 1
                      ? t.reading_n(current: _current, total: total)
                      : t.reading,
                  actions: [
                    TextButton(
                      key: const Key('receipt-cancel'),
                      onPressed: _cancel,
                      child: Text(t.cancel),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
