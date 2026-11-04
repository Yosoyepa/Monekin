import 'package:flutter/material.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';

/// Rebuilds with the number of pending inbox items.
class InboxPendingBuilder extends StatefulWidget {
  const InboxPendingBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, int count) builder;

  @override
  State<InboxPendingBuilder> createState() => _InboxPendingBuilderState();
}

class _InboxPendingBuilderState extends State<InboxPendingBuilder> {
  late final Stream<int> _count = InboxService.instance.watchPendingCount();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _count,
      initialData: 0,
      builder: (context, snapshot) =>
          widget.builder(context, snapshot.data ?? 0),
    );
  }
}

/// Brand badge with the pending count; hidden when it is zero.
class PendingBadge extends StatelessWidget {
  const PendingBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: scheme.primary,
      textColor: scheme.onPrimary,
      textStyle: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontFeatures: tabularFigures,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      label: Text(count > 99 ? '99+' : '$count'),
      child: child,
    );
  }
}
