// Account picker of the inbox review (T002). Owner: w-inbox.
// Savings accounts (`isSaving`) only accept transfers in Monekin, so they are
// listed with a note and must be unmarked before they receive a row.
import 'package:flutter/material.dart';
import 'package:monekin/app/accounts/account_form.dart';
import 'package:monekin/core/database/services/account/account_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/presentation/widgets/modal_container.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// Reads the accounts the picker lists and clears the savings flag of one.
/// Tests pass their own source; the app uses [AccountService].
abstract class InboxAccountSource {
  Future<List<Account>> accounts();

  /// Stores `isSaving = false` and returns the account as stored now.
  Future<Account?> clearSavingFlag(Account account);
}

class MonekinInboxAccountSource implements InboxAccountSource {
  const MonekinInboxAccountSource();

  @override
  Future<List<Account>> accounts() =>
      AccountService.instance.getAccounts().first;

  @override
  Future<Account?> clearSavingFlag(Account account) async {
    await AccountService.instance.updateAccount(
      account.copyWith(isSaving: false),
    );
    return AccountService.instance.getAccountById(account.id).first;
  }
}

/// Shows the picker as a responsive modal and returns the chosen account.
Future<Account?> showInboxAccountPicker(
  BuildContext context, {
  Account? current,
  InboxAccountSource source = const MonekinInboxAccountSource(),
}) {
  return RouteUtils.showResponsiveModal<Account>(
    context,
    builder: (_) => InboxAccountPicker(
      current: current,
      source: source,
      onChosen: (account) => RouteUtils.popRoute(account),
    ),
  );
}

class InboxAccountPicker extends StatefulWidget {
  const InboxAccountPicker({
    super.key,
    required this.onChosen,
    this.current,
    this.source = const MonekinInboxAccountSource(),
    this.onCreateAccount,
  });

  final Account? current;
  final InboxAccountSource source;
  final ValueChanged<Account> onChosen;

  /// Opens the account form. Defaults to the Monekin form.
  final Future<void> Function(BuildContext context)? onCreateAccount;

  @override
  State<InboxAccountPicker> createState() => _InboxAccountPickerState();
}

class _InboxAccountPickerState extends State<InboxAccountPicker> {
  late Future<List<Account>> _accounts;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _accounts = _load();
  }

  /// Open accounts only: a closed one cannot receive new rows.
  Future<List<Account>> _load() async => [
    for (final account in await widget.source.accounts())
      if (account.closingDate == null) account,
  ];

  Future<void> _create() async {
    final create = widget.onCreateAccount ?? _openAccountForm;
    await create(context);
    if (!mounted) return;
    setState(() => _accounts = _load());
  }

  Future<void> _choose(Account account) async {
    if (!account.isSaving) {
      widget.onChosen(account);
      return;
    }

    final unmark = await showDialog<bool>(
      context: context,
      builder: (context) => _savingDialog(context, account),
    );
    if (unmark != true || !mounted) return;

    final stored = await widget.source.clearSavingFlag(account);
    if (stored != null && mounted) widget.onChosen(stored);
  }

  static Future<void> _openAccountForm(BuildContext context) async {
    await RouteUtils.showResponsiveForm(const AccountFormPage());
  }

  Widget _savingDialog(BuildContext context, Account account) {
    final t = Translations.of(context);

    return AlertDialog(
      content: Text(t.ia_inbox.saving_dialog_body(name: account.name)),
      actions: [
        TextButton(
          key: const Key('inbox-saving-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.ia_inbox.cancel),
        ),
        FilledButton(
          key: const Key('inbox-saving-unmark'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.ia_inbox.saving_dialog_confirm),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return ModalContainer(
      title: t.account.select.one,
      body: FutureBuilder<List<Account>>(
        future: _accounts,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LinearProgressIndicator();

          final all = snapshot.data!;
          final query = _search.trim().toLowerCase();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: t.general.tap_to_search,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: all.isEmpty
                      ? Center(
                          child: Text(
                            t.ia_inbox.no_accounts_hint,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView(
                          children: [
                            for (final account in all)
                              if (account.name.toLowerCase().contains(query))
                                ListTile(
                                  key: Key('inbox-account-${account.id}'),
                                  leading: account.displayIcon(context),
                                  title: Text(account.name),
                                  subtitle: account.isSaving
                                      ? Text(t.ia_inbox.saving_subtitle)
                                      : null,
                                  selected: account.id == widget.current?.id,
                                  onTap: () => _choose(account),
                                ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('inbox-account-create'),
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(t.ia_inbox.create_account),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
