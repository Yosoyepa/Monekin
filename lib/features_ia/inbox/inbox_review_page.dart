// Review page of one inbox item (T002). Owner: w-inbox.
// Rows are editable; nothing is written until the user confirms.
import 'package:flutter/material.dart';
import 'package:monekin/app/accounts/account_selector.dart';
import 'package:monekin/app/categories/selectors/category_picker.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/core/database/services/account/account_service.dart';
import 'package:monekin/core/database/services/category/category_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/models/category/category.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/presentation/widgets/expanding_segmented_tabs.dart';
import 'package:monekin/core/presentation/widgets/inline_info_card.dart';
import 'package:monekin/core/utils/date_time_picker.dart';
import 'package:monekin/features_ia/core/money/amount_parser.dart';
import 'package:monekin/features_ia/inbox/attachment_thumbnail.dart';
import 'package:monekin/features_ia/inbox/drift_inbox_service.dart';
import 'package:monekin/features_ia/inbox/inbox_models.dart';
import 'package:monekin/features_ia/inbox/inbox_service.dart';
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
  Future<Account?> pickAccount(BuildContext context, Account? current) async {
    final res = await showAccountSelectorBottomSheet(
      context,
      AccountSelectorModal(
        allowMultiSelection: false,
        filterSavingAccounts: true,
        includeArchivedAccounts: false,
        selectedAccounts: [?current],
      ),
    );

    return res?.firstOrNull;
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
}

class InboxReviewPage extends StatefulWidget {
  const InboxReviewPage({
    super.key,
    required this.itemId,
    this.service,
    this.lookup = const MonekinInboxReviewLookup(),
    this.parseAmount = parseLocalizedAmount,
  });

  final String itemId;

  /// Defaults to [InboxService.instance].
  final InboxService? service;
  final InboxReviewLookup lookup;
  final AmountParser parseAmount;

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

  bool get _editable => _item?.status == InboxStatus.pending && !_busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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

    setState(() {
      _item = item;
      _rows = rows;
      _loaded = true;
    });

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
      _duplicates = result.duplicates;
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
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(context, item),
          if (_result != null) _resultCard(context, _result!),
          for (var i = 0; i < _rows.length; i++) _rowCard(context, i),
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
      persistentFooterButtons: item == null ? null : _footer(context, item),
    );
  }

  List<Widget>? _footer(BuildContext context, InboxItem item) {
    final t = Translations.of(context);

    if (item.status != InboxStatus.pending) {
      return [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.ia_inbox.close),
        ),
      ];
    }

    return [
      OutlinedButton(
        onPressed: _busy ? null : _discard,
        child: Text(t.ia_inbox.discard),
      ),
      FilledButton(
        onPressed: _busy || _rows.isEmpty || _rows.any((r) => !r.amountValid)
            ? null
            : _confirm,
        child: Text(t.ia_inbox.confirm),
      ),
    ];
  }

  Widget _header(BuildContext context, InboxItem item) {
    final t = Translations.of(context);
    final sourceLabel = switch (item.source) {
      InboxSource.receipt => t.ia_inbox.source_receipt,
      InboxSource.statement => t.ia_inbox.source_statement,
      InboxSource.notification => t.ia_inbox.source_notification,
    };

    final info = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.attachmentPaths.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: AttachmentThumbnail(
                key: const Key('inbox-attachment'),
                path: item.attachmentPaths.first,
                size: 96,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sourceLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(item.sourceRef),
                Text(DateFormat.yMMMd().add_Hm().format(item.createdAt)),
              ],
            ),
          ),
        ],
      ),
    );

    final note = item.note;
    final rawText = item.rawText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        info,
        if (note != null && note.isNotEmpty)
          InlineInfoCard(
            key: const Key('inbox-note'),
            margin: const EdgeInsets.only(bottom: 16),
            text: note,
            mode: InlineInfoCardMode.info,
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
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SelectableText(rawText),
              ],
            ),
          ),
      ],
    );
  }

  Widget _resultCard(BuildContext context, ConfirmResult result) {
    final t = Translations.of(context);

    return Card(
      key: const Key('inbox-result'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.ia_inbox.result_title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(t.ia_inbox.result_created(n: result.createdIds.length)),
            if (result.duplicates.isNotEmpty)
              Text(t.ia_inbox.result_duplicates(n: result.duplicates.length)),
            if (result.errors.isNotEmpty)
              Text(t.ia_inbox.result_errors(n: result.errors.length)),
          ],
        ),
      ),
    );
  }

  Widget _rowCard(BuildContext context, int index) {
    final t = Translations.of(context);
    final state = _rows[index];
    final row = state.row;
    final editable = _editable;
    final dateFormat = DateFormat.yMMMd().add_Hm();
    final duplicate = _duplicates.where((d) => d.rowIndex == index).firstOrNull;

    final warnings = <String>[
      if (row.warning != null && row.warning!.isNotEmpty) row.warning!,
      if (state.account == null) t.ia_inbox.choose_account,
      if (state.category == null) t.ia_inbox.choose_category,
      if (state.account != null && state.account!.date.compareTo(row.date) > 0)
        t.transaction.form.validators.date_after_account_creation,
      if (_result?.errors[index] != null) _result!.errors[index]!,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in warnings)
              InlineInfoCard(
                margin: const EdgeInsets.only(bottom: 12),
                text: w,
                mode: InlineInfoCardMode.warn,
              ),
            if (editable)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  key: Key('inbox-remove-$index'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _removeRow(index),
                ),
              ),
            if (duplicate != null) ...[
              InlineInfoCard(
                key: Key('inbox-duplicate-$index'),
                margin: const EdgeInsets.only(bottom: 4),
                text: '${t.ia_inbox.duplicate_warning}: ${duplicate.reason}',
                mode: InlineInfoCardMode.warn,
              ),
              CheckboxListTile(
                key: Key('inbox-force-$index'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(t.ia_inbox.create_anyway),
                value: row.allowDuplicate,
                onChanged: editable
                    ? (v) => setState(() => row.allowDuplicate = v ?? false)
                    : null,
              ),
            ],
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
            ListTile(
              key: Key('inbox-date-$index'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(dateFormat.format(row.date)),
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
            ListTile(
              key: Key('inbox-category-$index'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.category_outlined),
              title: Text(state.category?.name ?? t.ia_inbox.choose_category),
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
            ListTile(
              key: Key('inbox-account-$index'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(state.account?.name ?? t.ia_inbox.choose_account),
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
