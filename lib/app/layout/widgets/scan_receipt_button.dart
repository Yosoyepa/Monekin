import 'package:flutter/material.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/features_ia/receipts/receipt_capture.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// Same hero tag the old small receipt button used.
const scanReceiptHeroTag = 'finanzas-ia-receipt-fab';

/// Round 56 dp "Scan receipt" button at the center of the bottom bar. It
/// shrinks while pressed and springs back with a short bounce.
class ScanReceiptButton extends StatefulWidget {
  const ScanReceiptButton({super.key});

  @override
  State<ScanReceiptButton> createState() => _ScanReceiptButtonState();
}

class _ScanReceiptButtonState extends State<ScanReceiptButton> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = BrandMotion.of(context);
    final label = Translations.of(context).brand_app.nav_scan_receipt;

    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && !motion.reduce ? 0.9 : 1,
        duration: motion.tap,
        curve: _pressed ? motion.enter : motion.bounce,
        child: FloatingActionButton(
          heroTag: scanReceiptHeroTag,
          tooltip: label,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          disabledElevation: 0,
          shape: const CircleBorder(),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          onPressed: () => startReceiptCapture(context),
          child: const Icon(Icons.document_scanner_rounded),
        ),
      ),
    );
  }
}

/// Compact scan action for the side navigation (tablet and desktop).
class SidebarScanReceiptButton extends StatelessWidget {
  const SidebarScanReceiptButton({super.key, this.extended = false});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final label = Translations.of(context).brand_app.nav_scan_receipt;

    if (extended) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => startReceiptCapture(context),
            icon: const Icon(Icons.document_scanner_rounded),
            label: Text(label),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IconButton.filledTonal(
        tooltip: label,
        onPressed: () => startReceiptCapture(context),
        icon: const Icon(Icons.document_scanner_rounded),
      ),
    );
  }
}
