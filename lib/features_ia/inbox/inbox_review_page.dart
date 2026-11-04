// Review page of one inbox item (T002). Owner: w-inbox.
// Rows are editable; nothing is written until the user confirms.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:monekin/app/transactions/details/transaction_details.page.dart';
import 'package:monekin/core/database/services/transaction/transaction_service.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/core/dedupe/dedupe.dart' as dedupe;
import 'package:monekin/app/categories/selectors/category_picker.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/core/database/services/account/account_service.dart';
import 'package:monekin/core/database/services/category/category_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/presentation/widgets/expanding_segmented_tabs.dart';
import 'package:monekin/core/utils/date_time_picker.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/core/consent/ai_consent_sheet.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/inbox/attachment_thumbnail.dart';
import 'package:monekin/features_ia/inbox/drift_inbox_service.dart';
import 'package:monekin/features_ia/inbox/inbox_account_picker.dart';
import 'package:monekin/features_ia/inbox/inbox_item_labels.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
import 'package:monekin/features_ia/notifications/notification_processor.dart';
import 'package:monekin/features_ia/statements/reconciliation_card.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:intl/intl.dart';

typedef AmountParser = double? Function(String raw);

/// Reads and picks the accounts and categories the rows refer to. Separated
/// from the page so the page can be tested without a database.
abstract class InboxReviewLookup {
  Future<Account?> account(String id);

  Future<Category?> category(String id);

  Future<Account?> pickAccount(BuildContext context, Account? current);

  Future<Category?> pickCategory(
    BuildContext context,
    Category? current,
    TransactionType type,
  );

  /// Any category, for the bulk action: each row keeps only the ones it fits.
  Future<Category?> pickAnyCategory(BuildContext context);
}

/// Uses the Monekin services and selectors.
class MonekinInboxReviewLookup implements InboxReviewLookup {
  const MonekinInboxReviewLookup();

  @override
  Future<Account?> account(String id) =>
      AccountService.instance.getAccountById(id).first;

  @override
  Future<Category?> category(String id) =>
      CategoryService.instance.getCategoryById(id).first;

  @override
  Future<Account?> pickAccount(BuildContext context, Account? current) {
    return showInboxAccountPicker(context, current: current);
  }

  @override
  Future<Category?> pickCategory(
    BuildContext context,
    Category? current,
    TransactionType type,
  ) {
    return showCategoryPickerModal(
      context,
      modal: CategoryPicker(
        selectedCategory: current,
        categoryType: type == TransactionType.income
            ? [CategoryType.I, CategoryType.B]
            : [CategoryType.E, CategoryType.B],
      ),
    );
  }

  @override
  Future<Category?> pickAnyCategory(BuildContext context) {
    return showCategoryPickerModal(
      context,
      modal: CategoryPicker(
        selectedCategory: null,
        categoryType: const [CategoryType.E, CategoryType.I, CategoryType.B],
      ),
    );
  }
}

class InboxReviewPage extends StatefulWidget {
  const InboxReviewPage({
    super.key,
    required this.itemId,
    this.service,
    this.lookup = const MonekinInboxReviewLookup(),
    this.parseAmount = parseLocalizedAmount,
    this.readNotice,
  });

  final String itemId;

  /// Defaults to [InboxService.instance].
  final InboxService? service;
  final InboxReviewLookup lookup;
  final AmountParser parseAmount;

  /// Reads a notice that waits for the AI. Defaults to [NotificationProcessor.readWithAi].
  final Future<NoticeReadResult> Function(InboxItem item)? readNotice;

  @override
  State<InboxReviewPage> createState() => _InboxReviewPageState();
}

class _RowState {
  _RowState(this.row)
    : title = TextEditingController(text: row.title),
      amount = TextEditingController(text: formatAmount(row.amount)),
      amountValid = row.amount > 0;

  final ProposedTransaction row;
  final TextEditingController title;
  final TextEditingController amount;
  Account? account;
  Category? category;

  /// False while the amount text is not a valid amount.
  bool amountValid;

  void dispose() {
    title.dispose();
    amount.dispose();
  }
}

/// `45900` -> `45900`, `12.34` -> `12,34` (the form the parser reads back).
String formatAmount(double amount) => amount <= 0
    ? ''
    : amount == amount.roundToDouble()
    ? amount.toInt().toString()
    : amount.toString().replaceAll('.', ',');

class _InboxReviewPageState extends State<InboxReviewPage> {
  InboxService get _service => widget.service ?? InboxService.instance;

  InboxItem? _item;
  bool _loaded = false;
  bool _busy = false;
  List<_RowState> _rows = [];
  List<DuplicateWarning> _duplicates = const [];
  ConfirmResult? _result;
  ({int applied, int skipped})? _bulk;

  /// Everything was created: Chanchi celebrates and the page closes.
  bool _celebrating = false;
  Timer? _closeTimer;

  bool get _editable =>
      _item?.status == InboxStatus.pending && !_busy && !_celebrating;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final item = await _service.getItem(widget.itemId);
    final rows = [
      for (final p in item?.proposals ?? const <ProposedTransaction>[])
        _RowState(p),
    ];

    for (final r in rows) {
      await _resolveNames(r);
    }

    if (!mounted) return;

    final previous = _rows;
    setState(() {
      _item = item;
      _rows = rows;
      _loaded = true;
    });
    for (final r in previous) {
      r.dispose();
    }

    await _refreshDuplicates();
  }

  Future<void> _resolveNames(_RowState r) async {
    final accountId = r.row.accountId;
    final categoryId = r.row.categoryId;

    r.account = accountId == null
        ? null
        : await widget.lookup.account(accountId);
    r.category = categoryId == null
        ? null
        : await widget.lookup.category(categoryId);
  }

  Future<void> _refreshDuplicates() async {
    final service = _service;
    final item = _item;

    if (service is! InboxDuplicatePreview || item == null || !_editable) return;

    final warnings = await (service as InboxDuplicatePreview).previewDuplicates(
      [for (final r in _rows) r.row],
    );
    final created = item.resultTransactionIds.toSet();

    if (!mounted) return;

    setState(() {
      _duplicates = [
        for (final w in warnings)
          if (!created.contains(w.existingTransactionId)) w,
      ];
    });
  }

  void _changed(VoidCallback edit) {
    setState(edit);
    _refreshDuplicates();
  }

  bool _readingWithAi = false;

  /// The user taps «Read with AI»: asks once to allow notices, then sends the sentence shown on the card.
  Future<void> _readWithAi(InboxItem item) async {
    if (!await ensureAiConsent(context, AiFeature.notice) || !mounted) return;
    setState(() => _readingWithAi = true);
    final result =
        await (widget.readNotice ??
            (item) => NotificationProcessor().readWithAi(item))(item);
    if (!mounted) return;
    setState(() => _readingWithAi = false);
    final t = Translations.of(context).ia_inbox;
    switch (result) {
      case NoticeReadResult.limit:
        _say(t.ai_limit_reached);
      case NoticeReadResult.failed:
        _say(t.ai_read_failed);
      case NoticeReadResult.read ||
          NoticeReadResult.notMoney ||
          NoticeReadResult.unclear:
        await _load();
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _addRow() {
    _changed(() {
      _rows.add(
        _RowState(
          ProposedTransaction(date: DateTime.now(), title: '', amount: 0),
        ),
      );
    });
  }

  void _removeRow(int index) {
    _changed(() => _rows.removeAt(index).dispose());
  }

  /// Rows still to categorize: pending or failed rows without a category.
  List<_RowState> get _uncategorized => [
    for (final r in _rows)
      if (r.row.categoryId == null &&
          (r.row.status == ProposalStatus.pending ||
              r.row.status == ProposalStatus.error))
        r,
  ];

  /// Applies one category to the uncategorized rows it fits; the rest keep none.
  Future<void> _chooseCategoryForRows() async {
    final category = await widget.lookup.pickAnyCategory(context);
    if (category == null || !mounted) return;

    _changed(() {
      final rows = _uncategorized;
      var applied = 0;
      for (final state in rows) {
        if (!category.type.matchWithTransactionType(state.row.type)) continue;
        state.category = category;
        state.row.categoryId = category.id;
        applied++;
      }
      _bulk = (applied: applied, skipped: rows.length - applied);
    });
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);

    final result = await _service.confirm(widget.itemId, [
      for (final r in _rows) r.row,
    ]);
    final item = await _service.getItem(widget.itemId);

    if (!mounted) return;

    setState(() {
      _busy = false;
      _result = result;
      _item = item;
      if (item != null) {
        final oldRows = _rows;
        _rows = [for (final p in item.proposals) _RowState(p)];
        for (final r in oldRows) {
          r.dispose();
        }
      }
      _duplicates = result.duplicates;
    });

    if (result.errors.isEmpty &&
        result.duplicates.isEmpty &&
        item?.status == InboxStatus.processed) {
      _celebrate();
      return;
    }

    for (final r in _rows) {
      await _resolveNames(r);
    }
    if (mounted) {
      setState(() {});
      await _refreshDuplicates();
    }
  }

  /// Chanchi `happy` for 1.2 s, then the page closes. With reduced motion it
  /// closes at once.
  void _celebrate() {
    if (BrandMotion.of(context).reduce) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _celebrating = true);
    _closeTimer = Timer(BrandDurations.chanchiLong, () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _discard() async {
    await _service.discard(widget.itemId);

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final item = _item;

    final Widget body;

    if (!_loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (item == null) {
      body = Center(child: Text(t.ia_inbox.item_missing));
    } else if (_celebrating) {
      body = IaStatusView(
        key: const Key('inbox-celebration'),
        mood: ChanchiMood.happy,
        title: t.ia_inbox.saved_title,
        message: t.ia_inbox.result_created(n: _result?.createdIds.length ?? 0),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(
          BrandTokens.pageMargin,
          8,
          BrandTokens.pageMargin,
          24,
        ),
        children: [
          _header(context, item),
          if (_result != null) _resultCard(context, _result!),
          for (var i = 0; i < _rows.length; i++) _rowCard(context, i),
          if (_editable && _uncategorized.isNotEmpty) _bulkCard(context),
          if (_bulk case final bulk?)
            IaNotice(
              key: const Key('inbox-bulk-note'),
              margin: const EdgeInsets.only(bottom: 16),
              text: [
                if (bulk.applied > 0) t.ia_inbox.bulk_applied(n: bulk.applied),
                if (bulk.skipped > 0) t.ia_inbox.bulk_skipped(n: bulk.skipped),
              ].join(' '),
              tone: IaTone.info,
            ),
          if (_editable)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const Key('inbox-add-row'),
                onPressed: _addRow,
                icon: const Icon(Icons.add_rounded),
                label: Text(t.ia_inbox.add_row),
              ),
            ),
        ],
      );
    }

    return PageFramework(
      title: t.ia_inbox.review_title,
      body: body,
      bottomNavigationBar: item == null || _celebrating
          ? null
          : _footer(context, item),
    );
  }

  Widget _footer(BuildContext context, InboxItem item) {
    final t = Translations.of(context);
    final Widget buttons;

    if (item.status != InboxStatus.pending) {
      buttons = FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(t.ia_inbox.close),
      );
    } else {
      buttons = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _discard,
              child: Text(t.ia_inbox.discard),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed:
                  _busy || _rows.isEmpty || _rows.any((r) => !r.amountValid)
                  ? null
                  : _confirm,
              child: Text(t.ia_inbox.confirm),
            ),
          ),
        ],
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          BrandTokens.pageMargin,
          8,
          BrandTokens.pageMargin,
          12,
        ),
        child: buttons,
      ),
    );
  }

  Widget _header(BuildContext context, InboxItem item) {
    final t = Translations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final secondary = BrandColors.of(context).textSecondary;
    final photo = item.attachmentPaths.firstOrNull;

    final info = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (photo != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: AttachmentThumbnail(
                key: const Key('inbox-attachment'),
                path: photo,
                size: 88,
                heroTag: inboxPhotoHeroTag(item.id),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inboxItemTitle(t, item),
                  key: const Key('inbox-title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat.yMMMd().add_Hm().format(item.createdAt),
                  style: textTheme.bodyMedium?.copyWith(color: secondary),
                ),
                const SizedBox(height: 8),
                IaChip(
                  label: inboxSourceLabel(t, item.source),
                  icon: inboxSourceIcon(item.source),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final note = item.note;
    final rawText = item.rawText;
    final reconciliation = item.source == InboxSource.statement
        ? reconciliationFromData(item.data) ??
              (note == null ? null : parseReconciliationNote(note))
        : null;
    final aiText = inboxItemAiText(item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        info,
        if (aiText != null) _aiNoticeCard(context, item, aiText),
        if (reconciliation != null)
          ReconciliationCard(
            reconciliation: reconciliation,
            format: _moneyFormat(),
            margin: const EdgeInsets.only(bottom: 16),
          )
        else if (note != null && note.isNotEmpty)
          IaNotice(
            key: const Key('inbox-note'),
            margin: const EdgeInsets.only(bottom: 16),
            text: note,
            tone: IaTone.info,
          ),
        if (rawText != null && rawText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              key: const Key('inbox-raw-text'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.ia_inbox.original_text,
                  style: textTheme.labelLarge?.copyWith(color: secondary),
                ),
                const SizedBox(height: 4),
                SelectableText(rawText),
              ],
            ),
          ),
      ],
    );
  }

  /// A notice the app did not understand on this phone: the exact sentence the AI would get, and the button that sends it.
  Widget _aiNoticeCard(BuildContext context, InboxItem item, String aiText) {
    final t = Translations.of(context).ia_inbox;
    final textTheme = Theme.of(context).textTheme;

    return IaCard(
      key: const Key('inbox-ai-notice'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.ai_notice_pending, style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(t.ai_notice_hint),
          const SizedBox(height: 12),
          SelectableText(
            aiText,
            key: const Key('inbox-ai-text'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: ['Consolas', 'Courier New'],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('inbox-read-ai'),
            onPressed: _readingWithAi || !_editable
                ? null
                : () => unawaited(_readWithAi(item)),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(t.read_with_ai),
          ),
        ],
      ),
    );
  }

  /// Currency of the first row that has an account.
  NumberFormat _moneyFormat() {
    final account = _rows.map((r) => r.account).nonNulls.firstOrNull;

    return iaMoneyFormat(
      symbol: account?.currency.symbol,
      decimals: account?.currency.decimalPlaces,
    );
  }

  Widget _bulkCard(BuildContext context) {
    final t = Translations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return IaCard(
      key: const Key('inbox-bulk-category'),
      onTap: _chooseCategoryForRows,
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.category_outlined, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t.ia_inbox.bulk_category(n: _uncategorized.length),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onPrimaryContainer),
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context, ConfirmResult result) {
    final t = Translations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return IaCard(
      key: const Key('inbox-result'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.ia_inbox.result_title, style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(t.ia_inbox.result_created(n: result.createdIds.length)),
          if (result.duplicates.isNotEmpty)
            Text(t.ia_inbox.result_duplicates(n: result.duplicates.length)),
          for (final duplicate in result.duplicates)
            Text(
              t.ia_inbox.skipped_row(
                n: duplicate.rowIndex + 1,
                reason: _duplicateReason(context, duplicate.reason),
              ),
            ),
          if (result.errors.isNotEmpty)
            Text(t.ia_inbox.result_errors(n: result.errors.length)),
        ],
      ),
    );
  }

  String _duplicateReason(BuildContext context, String reason) {
    final t = Translations.of(context);
    return reason == dedupe.duplicateInBatch
        ? t.ia_inbox.duplicate_batch
        : t.ia_inbox.duplicate_existing;
  }

  /// A tappable field-like row: icon, value and a chevron.
  Widget _selector(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String text,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final brand = BrandColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        key: key,
        color: brand.surfaceLow,
        borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, color: scheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text)),
                  if (enabled)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: brand.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowCard(BuildContext context, int index) {
    final t = Translations.of(context);
    final state = _rows[index];
    final row = state.row;
    final editable =
        _editable &&
        (row.status == ProposalStatus.pending ||
            row.status == ProposalStatus.error);
    final dateFormat = DateFormat.yMMMd().add_Hm();
    final duplicate = _duplicates.where((d) => d.rowIndex == index).firstOrNull;
    final textTheme = Theme.of(context).textTheme;

    final warnings = <String>[
      if (row.warning != null && row.warning!.isNotEmpty) row.warning!,
      if (state.account == null) t.ia_inbox.choose_account,
      if (state.category == null) t.ia_inbox.choose_category,
      if (state.account != null && state.account!.date.compareTo(row.date) > 0)
        t.transaction.form.validators.date_after_account_creation,
      if (row.errorMessage != null && row.status == ProposalStatus.error)
        row.errorMessage!,
      if (_result?.errors[index] != null &&
          _result!.errors[index] != row.errorMessage)
        _result!.errors[index]!,
    ];

    final format = iaMoneyFormat(
      symbol: state.account?.currency.symbol,
      decimals: state.account?.currency.decimalPlaces,
    );

    return StaggeredEntrance(
      index: index + 1,
      child: IaCard(
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: state.amountValid
                      ? IaMoneyText(
                          row.amount,
                          key: Key('inbox-money-$index'),
                          format: format,
                          income: row.type == TransactionType.income,
                          style: textTheme.headlineMedium,
                        )
                      : const SizedBox.shrink(),
                ),
                if (editable)
                  IconButton(
                    key: Key('inbox-remove-$index'),
                    tooltip: t.ui_actions.delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _removeRow(index),
                  ),
              ],
            ),
            for (final w in warnings)
              IaNotice(
                margin: const EdgeInsets.only(top: 8),
                text: w,
                tone: IaTone.warning,
              ),
            if (row.status == ProposalStatus.created &&
                row.transactionId != null)
              TextButton.icon(
                key: Key('inbox-created-$index'),
                icon: const Icon(Icons.open_in_new),
                label: Text(t.ia_inbox.open_transaction),
                onPressed: () async {
                  final transaction = await TransactionService.instance
                      .getTransactionById(row.transactionId!)
                      .first;
                  if (transaction != null && context.mounted) {
                    unawaited(
                      RouteUtils.pushRoute(
                        TransactionDetailsPage(
                          transaction: transaction,
                          heroTag: null,
                        ),
                      ),
                    );
                  }
                },
              ),
            if (row.status == ProposalStatus.skippedDuplicate)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.ia_inbox.skipped_row(
                    n: index + 1,
                    reason: _duplicateReason(context, row.errorMessage ?? ''),
                  ),
                ),
              ),
            if (duplicate != null) ...[
              IaNotice(
                key: Key('inbox-duplicate-$index'),
                margin: const EdgeInsets.only(top: 8),
                text:
                    '${t.ia_inbox.duplicate_warning}: ${_duplicateReason(context, duplicate.reason)}',
                tone: IaTone.warning,
              ),
              CheckboxListTile(
                key: Key('inbox-force-$index'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(t.ia_inbox.create_anyway),
                value: row.allowForReason(duplicate.reason),
                onChanged: editable
                    ? (v) => setState(() => row.allowDuplicate = v ?? false)
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            ExpandingSegmentedTabs<TransactionType>(
              items: [
                for (final type in [
                  TransactionType.expense,
                  TransactionType.income,
                ])
                  SegmentedTabItem(
                    value: type,
                    icon: type.icon,
                    label: type.displayName(context),
                  ),
              ],
              selected: row.type,
              onSelected: (type) {
                if (!editable) return;

                _changed(() {
                  row.type = type;

                  final category = state.category;
                  if (category != null &&
                      !category.type.matchWithTransactionType(type)) {
                    state.category = null;
                    row.categoryId = null;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: Key('inbox-title-$index'),
              controller: state.title,
              enabled: editable,
              decoration: InputDecoration(labelText: t.ia_inbox.field_title),
              onChanged: (v) => _changed(() => row.title = v),
            ),
            const SizedBox(height: 12),
            TextField(
              key: Key('inbox-amount-$index'),
              controller: state.amount,
              enabled: editable,
              style: const TextStyle(fontFeatures: tabularFigures),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: t.ia_inbox.field_amount,
                errorText: state.amountValid ? null : t.ia_inbox.amount_invalid,
              ),
              onChanged: (v) {
                final amount = widget.parseAmount(v);

                _changed(() {
                  state.amountValid = amount != null && amount > 0;
                  if (amount != null) row.amount = amount.abs();
                });
              },
            ),
            _selector(
              context,
              key: Key('inbox-date-$index'),
              icon: Icons.event_rounded,
              text: dateFormat.format(row.date),
              enabled: editable,
              onTap: () async {
                final date = await openDateTimePicker(
                  context,
                  initialDate: row.date,
                  showTimePickerAfterDate: true,
                );

                if (date != null) _changed(() => row.date = date);
              },
            ),
            _selector(
              context,
              key: Key('inbox-category-$index'),
              icon: Icons.category_outlined,
              text: state.category?.name ?? t.ia_inbox.choose_category,
              enabled: editable,
              onTap: () async {
                final category = await widget.lookup.pickCategory(
                  context,
                  state.category,
                  row.type,
                );

                if (category != null) {
                  _changed(() {
                    state.category = category;
                    row.categoryId = category.id;
                  });
                }
              },
            ),
            _selector(
              context,
              key: Key('inbox-account-$index'),
              icon: Icons.account_balance_wallet_outlined,
              text: state.account?.name ?? t.ia_inbox.choose_account,
              enabled: editable,
              onTap: () async {
                final account = await widget.lookup.pickAccount(
                  context,
                  state.account,
                );

                if (account != null) {
                  _changed(() {
                    state.account = account;
                    row.accountId = account.id;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
