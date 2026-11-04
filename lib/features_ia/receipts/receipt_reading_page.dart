// «Reading receipt…» screen: analyzes the photos one by one and pops with the inbox item ids. Owner: w-recibos.
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final ids = <String>[];
    for (var i = 0; i < widget.photos.length; i++) {
      if (!mounted) return;
      setState(() => _current = i + 1);
      try {
        ids.add(
          await addReceiptToInbox(widget.photos[i], analyzer: widget.analyzer),
        );
      } catch (_) {
        // The photo stays on disk; the remaining receipts are still processed.
      }
    }
    if (mounted) Navigator.of(context).pop(ids);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_receipts;
    final total = widget.photos.length;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                total > 1
                    ? t.reading_n(current: _current, total: total)
                    : t.reading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
