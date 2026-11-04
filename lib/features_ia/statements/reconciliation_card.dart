// Reconciliation of an imported statement: its net movement and how far it is from the bank's balances.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

typedef Reconciliation = ({double net, double difference});

final _figure = RegExp(r'-?\d+\.\d{2}(?!\d)');

/// Reads the two figures out of the note the import writes (`reconciliation`
/// of IA-STATEMENTS: net first, then the difference). Null for any other text,
/// like the one for statements without balances.
Reconciliation? parseReconciliationNote(String note) {
  final figures = _figure
      .allMatches(note)
      .map((m) => double.parse(m.group(0)!))
      .toList();

  return figures.length == 2 ? (net: figures[0], difference: figures[1]) : null;
}

/// Net in income/expense color and a difference that is green when it is zero
/// and a warning when it is not.
class ReconciliationCard extends StatelessWidget {
  const ReconciliationCard({
    super.key,
    required this.reconciliation,
    required this.format,
    this.margin = EdgeInsets.zero,
  });

  final Reconciliation reconciliation;
  final NumberFormat format;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_statements;
    final textTheme = Theme.of(context).textTheme;
    final brand = BrandColors.of(context);
    final matches = reconciliation.difference.abs() < 0.005;
    final tone = matches ? IaTone.success : IaTone.warning;

    Widget figure(String label, Widget value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(color: brand.textSecondary),
          ),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );

    return IaCard(
      key: const Key('reconciliation-card'),
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.reconciliation_title, style: textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              figure(
                t.net_label,
                IaMoneyText(
                  reconciliation.net.abs(),
                  key: const Key('reconciliation-net'),
                  format: format,
                  income: reconciliation.net == 0
                      ? null
                      : reconciliation.net > 0,
                  style: textTheme.titleLarge,
                ),
              ),
              figure(
                t.difference_label,
                IaMoneyText(
                  reconciliation.difference.abs(),
                  key: const Key('reconciliation-difference'),
                  format: format,
                  income: matches ? true : null,
                  style: textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          IaNotice(
            key: const Key('reconciliation-verdict'),
            tone: tone,
            text: matches ? t.reconciled : t.not_reconciled,
          ),
        ],
      ),
    );
  }
}
