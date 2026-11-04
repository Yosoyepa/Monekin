// List of the AI inbox: pending, processed and discarded items (T002). Owner: w-inbox.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/presentation/widgets/expanding_segmented_tabs.dart';
import 'package:monekin/features_ia/inbox/attachment_thumbnail.dart';
import 'package:monekin/features_ia/inbox/inbox_item_labels.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_navigation.dart';
import 'package:monekin/features_ia/inbox/inbox_review_page.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/receipts/receipt_capture.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({
    super.key,
    this.service,
    this.onOpenItem,
    this.lookup = const MonekinInboxReviewLookup(),
    this.onScan,
  });

  /// Defaults to [InboxService.instance].
  final InboxService? service;

  /// Defaults to opening the review page.
  final void Function(BuildContext context, String itemId)? onOpenItem;

  /// Resolves the account of an item, to show its amount in that currency.
  final InboxReviewLookup lookup;

  /// Defaults to the receipt capture flow.
  final void Function(BuildContext context)? onScan;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  InboxStatus _status = InboxStatus.pending;

  InboxService get _service => widget.service ?? InboxService.instance;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PageFramework(
      title: t.ia_inbox.title,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BrandTokens.pageMargin,
              8,
              BrandTokens.pageMargin,
              12,
            ),
            child: StreamBuilder<int>(
              stream: _service.watchPendingCount(),
              builder: (context, snapshot) =>
                  ExpandingSegmentedTabs<InboxStatus>(
                    selected: _status,
                    onSelected: (s) => setState(() => _status = s),
                    items: [
                      SegmentedTabItem(
                        value: InboxStatus.pending,
                        icon: Icons.inbox_rounded,
                        label: t.ia_inbox.tab_pending,
                        badgeCount: snapshot.data,
                      ),
                      SegmentedTabItem(
                        value: InboxStatus.processed,
                        icon: Icons.check_circle_outline_rounded,
                        label: t.ia_inbox.tab_processed,
                      ),
                      SegmentedTabItem(
                        value: InboxStatus.discarded,
                        icon: Icons.delete_outline_rounded,
                        label: t.ia_inbox.tab_discarded,
                      ),
                    ],
                  ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<InboxItem>>(
              stream: _service.watchItems(status: _status),
              builder: (context, snapshot) {
                final items = snapshot.data;

                if (items == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (items.isEmpty) return _empty(context);

                return ListView.builder(
                  key: ValueKey(_status),
                  padding: const EdgeInsets.fromLTRB(
                    BrandTokens.pageMargin,
                    4,
                    BrandTokens.pageMargin,
                    24,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => StaggeredEntrance(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ItemCard(
                        item: items[i],
                        lookup: widget.lookup,
                        onTap: () => (widget.onOpenItem ?? openInboxReview)(
                          context,
                          items[i].id,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final t = Translations.of(context);
    final pending = _status == InboxStatus.pending;

    return IaStatusView(
      mood: ChanchiMood.sleepy,
      message: switch (_status) {
        InboxStatus.pending => t.ia_inbox.empty_pending,
        InboxStatus.processed => t.ia_inbox.empty_processed,
        InboxStatus.discarded => t.ia_inbox.empty_discarded,
      },
      actions: [
        if (pending)
          FilledButton.icon(
            key: const Key('inbox-scan'),
            onPressed: () => (widget.onScan ?? _scan)(context),
            icon: const Icon(Icons.document_scanner_outlined),
            label: Text(t.ia_inbox.scan_receipt),
          ),
      ],
    );
  }

  void _scan(BuildContext context) => unawaited(startReceiptCapture(context));
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    required this.item,
    required this.lookup,
    required this.onTap,
  });

  final InboxItem item;
  final InboxReviewLookup lookup;
  final VoidCallback onTap;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  Account? _account;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAccount());
  }

  /// Currency of the first row that has an account; without it the amount is
  /// shown as a plain number.
  Future<void> _loadAccount() async {
    final id = widget.item.proposals
        .map((p) => p.accountId)
        .nonNulls
        .firstOrNull;
    if (id == null) return;

    try {
      final account = await widget.lookup.account(id);
      if (mounted) setState(() => _account = account);
    } on Object {
      // The amount stays unformatted.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final item = widget.item;
    final textTheme = Theme.of(context).textTheme;
    final secondary = BrandColors.of(context).textSecondary;
    final photo = item.source == InboxSource.receipt
        ? item.attachmentPaths.firstOrNull
        : null;

    final rows = item.proposals.length;
    final subtitle = [
      inboxSourceLabel(t, item.source),
      if (rows != 1) t.ia_inbox.rows_count(n: rows),
      DateFormat.yMMMd().format(item.createdAt),
    ].join(' · ');

    final net = inboxItemNet(item);
    final format = iaMoneyFormat(
      symbol: _account?.currency.symbol,
      decimals: _account?.currency.decimalPlaces,
    );

    return IaCard(
      key: Key('inbox-item-${item.id}'),
      onTap: widget.onTap,
      child: Row(
        children: [
          if (photo != null)
            AttachmentThumbnail(
              path: photo,
              size: 52,
              heroTag: inboxPhotoHeroTag(item.id),
              opensFullScreen: false,
            )
          else
            IaAvatar(icon: inboxSourceIcon(item.source), size: 52),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inboxItemTitle(t, item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      inboxSourceIcon(item.source),
                      size: 14,
                      color: secondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(color: secondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (rows > 0)
                IaMoneyText(
                  net.abs(),
                  format: format,
                  income: net == 0 ? null : net > 0,
                ),
              if (rows > 0) const SizedBox(height: 4),
              _StatusChip(status: item.status),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final InboxStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_inbox;
    final brand = BrandColors.of(context);

    final (label, color) = switch (status) {
      InboxStatus.pending => (t.tab_pending, brand.warning),
      InboxStatus.processed => (t.tab_processed, brand.income),
      InboxStatus.discarded => (t.tab_discarded, brand.textSecondary),
    };

    return IaChip(label: label, color: color);
  }
}
