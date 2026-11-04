// List of the AI inbox: pending, processed and discarded items (T002). Owner: w-inbox.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/core/presentation/widgets/expanding_segmented_tabs.dart';
import 'package:monekin/core/presentation/widgets/no_results.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_navigation.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key, this.service, this.onOpenItem});

  /// Defaults to [InboxService.instance].
  final InboxService? service;

  /// Defaults to opening the review page.
  final void Function(BuildContext context, String itemId)? onOpenItem;

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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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

                if (items.isEmpty) {
                  return NoResults(
                    description: switch (_status) {
                      InboxStatus.pending => t.ia_inbox.empty_pending,
                      InboxStatus.processed => t.ia_inbox.empty_processed,
                      InboxStatus.discarded => t.ia_inbox.empty_discarded,
                    },
                  );
                }

                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => _tile(context, items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, InboxItem item) {
    final t = Translations.of(context);
    final icon = switch (item.source) {
      InboxSource.receipt => Icons.receipt_long_outlined,
      InboxSource.statement => Icons.description_outlined,
      InboxSource.notification => Icons.notifications_outlined,
    };

    return ListTile(
      key: Key('inbox-item-${item.id}'),
      leading: Icon(icon),
      title: Text(item.sourceRef, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${t.ia_inbox.rows_count(n: item.proposals.length)} · ${DateFormat.yMMMd().format(item.createdAt)}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => (widget.onOpenItem ?? openInboxReview)(context, item.id),
    );
  }
}
