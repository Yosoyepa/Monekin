// Cards and accounts page (T002). Owner: w-utils. Maps the last four digits of each card to a Monekin account.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monekin/app/accounts/account_selector.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/database/services/account/account_service.dart';
import 'package:monekin/core/models/account/account.dart';
import 'package:monekin/core/presentation/widgets/bottomSheetFooter.dart';
import 'package:monekin/core/presentation/widgets/modal_container.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/features_ia/core/cards/card_map.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class CardMapPage extends StatefulWidget {
  const CardMapPage({super.key});

  @override
  State<CardMapPage> createState() => _CardMapPageState();
}

class _CardMapPageState extends State<CardMapPage> {
  Map<String, String> _cards = {};
  List<Account> _accounts = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();

    unawaited(_load());
  }

  Future<void> _load() async {
    final cards = await CardMapService.instance.load();
    final accounts = await AccountService.instance.getAccounts().first;

    if (!mounted) return;

    setState(() {
      _cards = cards;
      _accounts = accounts;
      _loaded = true;
    });
  }

  Future<void> _saveCards(Map<String, String> cards) async {
    await CardMapService.instance.save(cards);

    if (!mounted) return;

    setState(() => _cards = cards);
  }

  Future<void> _addCard() async {
    final card =
        await RouteUtils.showResponsiveModal<
          ({String last4, String accountId})
        >(context, builder: (context) => const _CardForm());

    if (card == null) return;

    await _saveCards({..._cards, card.last4: card.accountId});
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final entries = _cards.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return PageFramework(
      title: t.ia_cards.title,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loaded ? () => unawaited(_addCard()) : null,
        icon: const Icon(Icons.add),
        label: Text(t.ia_cards.add),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
          ? IaStatusView(mood: ChanchiMood.sleepy, message: t.ia_cards.empty)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                BrandTokens.pageMargin,
                8,
                BrandTokens.pageMargin,
                96,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final account = _accounts.firstWhereOrNull(
                  (a) => a.id == entry.value,
                );

                return StaggeredEntrance(
                  index: index,
                  child: IaCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Semantics(
                          label: t.ia_cards.card_ending(digits: entry.key),
                          excludeSemantics: true,
                          child: IaChip(
                            icon: Icons.credit_card_rounded,
                            label: '•••• ${entry.key}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            account?.name ?? t.ia_cards.account_missing,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: t.ui_actions.delete,
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => unawaited(
                            _saveCards(Map.of(_cards)..remove(entry.key)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _CardForm extends StatefulWidget {
  const _CardForm();

  @override
  State<_CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<_CardForm> {
  final _last4Controller = TextEditingController();
  Account? _account;

  @override
  void dispose() {
    _last4Controller.dispose();
    super.dispose();
  }

  bool get _last4Valid => RegExp(r'^\d{4}$').hasMatch(_last4Controller.text);

  Future<void> _pickAccount() async {
    final selected = await showAccountSelectorBottomSheet(
      context,
      const AccountSelectorModal(
        allowMultiSelection: false,
        filterSavingAccounts: false,
        includeArchivedAccounts: false,
      ),
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() => _account = selected.first);
  }

  void _submit() {
    final account = _account;

    if (account == null || !_last4Valid) return;

    RouteUtils.popRoute((last4: _last4Controller.text, accountId: account.id));
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final showError = _last4Controller.text.isNotEmpty && !_last4Valid;

    return ModalContainer(
      title: t.ia_cards.add,
      bodyPadding: const EdgeInsets.symmetric(horizontal: 16),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _last4Controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: t.ia_cards.last4_label,
              errorText: showError ? t.ia_cards.last4_invalid : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(_account?.name ?? t.account.select.one),
            onTap: () => unawaited(_pickAccount()),
          ),
        ],
      ),
      footer: BottomSheetFooter(
        onSaved: _last4Valid && _account != null ? _submit : null,
      ),
    );
  }
}
