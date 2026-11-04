import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/core/consent/ai_consent_sheet.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:url_launcher/url_launcher.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  late final AiServiceImpl service;
  final url = TextEditingController();
  final model = TextEditingController();
  final key = TextEditingController();
  AiProviderId provider = AiProviderId.gemini;
  bool ready = false;
  bool busy = false;
  bool hasKey = false;
  bool keyToConfirm = false;
  Set<AiFeature> allowed = {};
  String? status;
  IaTone statusTone = IaTone.info;

  @override
  void initState() {
    super.initState();
    service = AiService.instance as AiServiceImpl;
    _load();
  }

  Future<void> _load() async {
    final config = await service.loadConfig();
    final savedKey = await service.hasKey(config);
    final toConfirm = await service.hasKeyToConfirm(config);
    final consent = await AiConsent.instance.granted(config);
    if (!mounted) return;
    setState(() {
      provider = config.provider;
      url.text = config.baseUrl;
      model.text = config.model;
      hasKey = savedKey;
      keyToConfirm = toConfirm;
      allowed = consent;
      ready = true;
    });
  }

  /// Turning a function off forgets its consent: the next use asks again. It is turned on from the sheet that asks.
  Future<void> _revoke(AiFeature feature) async {
    await AiConsent.instance.revoke(feature, await service.loadConfig());
    if (mounted) setState(() => allowed = {...allowed}..remove(feature));
  }

  AiProviderConfig get config => AiProviderConfig(
    provider: provider,
    baseUrl: url.text.trim(),
    model: model.text.trim(),
  );

  /// The key is stored per provider and host: show whether the selected destination has one.
  Future<void> _refreshHasKey() async {
    final asked = config;
    final saved = await service.hasKey(asked);
    final toConfirm = await service.hasKeyToConfirm(asked);
    if (!mounted ||
        AiServiceImpl.keyNameFor(asked) != AiServiceImpl.keyNameFor(config)) {
      return;
    }
    setState(() {
      hasKey = saved;
      keyToConfirm = toConfirm;
    });
  }

  Future<bool> _save() async {
    if (!isAllowedProviderUrl(config.baseUrl)) {
      setState(() {
        status = Translations.of(context).ia_settings.error_insecure_url;
        statusTone = IaTone.error;
      });
      return false;
    }
    final destination = config;
    await service.saveConfig(destination);
    if (key.text.trim().isNotEmpty) {
      await service.saveKey(key.text, destination);
      key.clear();
    }
    final savedKey = await service.hasKey(destination);
    final toConfirm = await service.hasKeyToConfirm(destination);
    final consent = await AiConsent.instance.granted(destination);
    if (mounted) {
      setState(() {
        hasKey = savedKey;
        keyToConfirm = toConfirm;
        allowed = consent;
        status = Translations.of(context).ia_settings.saved;
        statusTone = IaTone.info;
      });
    }
    return true;
  }

  Future<void> _delete() async {
    await service.deleteKey(config);
    key.clear();
    if (mounted) {
      setState(() {
        hasKey = false;
        keyToConfirm = false;
        status = Translations.of(context).ia_settings.key_deleted;
        statusTone = IaTone.info;
      });
    }
  }

  String _error(AiException error) {
    final strings = Translations.of(context).ia_settings;
    return switch (error.kind) {
      AiErrorKind.notConfigured => strings.error_config,
      AiErrorKind.invalidKey => strings.error_key,
      AiErrorKind.quotaExceeded => '${strings.error_quota} ${error.message}',
      AiErrorKind.network => strings.error_network,
      AiErrorKind.timeout => strings.error_timeout,
      AiErrorKind.badResponse || AiErrorKind.unknown => strings.error_response,
    };
  }

  Future<void> _testConnection() async {
    if (!await _save()) return;
    if (!mounted) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      final client = await service.client();
      await client.listModels();
      await client.chat([
        const AiMessage.user('Reply with an empty JSON object.'),
      ]);
      if (mounted) {
        setState(() {
          status = Translations.of(context).ia_settings.connected;
          statusTone = IaTone.success;
        });
      }
    } on AiException catch (error) {
      if (mounted) {
        setState(() {
          status = _error(error);
          statusTone = IaTone.error;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _chooseModel() async {
    if (!await _save()) return;
    if (!mounted) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      final client = await service.clientForModels(config);
      final models = await client.listModels();
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => _ModelDialog(models: models),
      );
      if (selected != null && mounted) setState(() => model.text = selected);
    } on AiException catch (error) {
      if (mounted) {
        setState(() {
          status = _error(error);
          statusTone = IaTone.error;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    url.dispose();
    model.dispose();
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Translations.of(context).ia_settings;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(strings.title)),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                BrandTokens.pageMargin,
                8,
                BrandTokens.pageMargin,
                32,
              ),
              children: [
                Text(strings.provider, style: textTheme.titleMedium),
                const SizedBox(height: 12),
                _providerGrid(),
                const SizedBox(height: 24),
                TextField(
                  key: const ValueKey('ai-url'),
                  controller: url,
                  readOnly: provider != AiProviderId.custom,
                  decoration: InputDecoration(labelText: strings.base_url),
                  onChanged: (_) {
                    setState(() {
                      hasKey = false;
                      keyToConfirm = false;
                    });
                    unawaited(_refreshHasKey());
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('ai-key'),
                  controller: key,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.api_key,
                    hintText: hasKey ? strings.key_saved : null,
                    prefixIcon: Icon(
                      hasKey ? Icons.lock_rounded : Icons.key_rounded,
                    ),
                    suffixIcon: IconButton(
                      tooltip: strings.paste,
                      onPressed: () async {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (mounted && data?.text != null) {
                          key.text = data!.text!;
                        }
                      },
                      icon: const Icon(Icons.paste),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (keyToConfirm && !hasKey) ...[
                  IaNotice(
                    key: const ValueKey('ai-key-to-confirm'),
                    tone: IaTone.warning,
                    icon: Icons.key_rounded,
                    text: strings.key_to_confirm,
                  ),
                  const SizedBox(height: 8),
                ],
                IaNotice(
                  tone: IaTone.info,
                  icon: Icons.link_rounded,
                  text: strings.key_per_destination,
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('ai-delete'),
                    onPressed: busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(strings.delete_key),
                    style: TextButton.styleFrom(
                      foregroundColor: BrandColors.of(context).expense,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: model,
                  decoration: InputDecoration(
                    labelText: strings.model,
                    suffixIcon: IconButton(
                      tooltip: strings.choose_model,
                      onPressed: busy ? null : _chooseModel,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('ai-save'),
                        onPressed: busy ? null : _save,
                        child: Text(strings.save),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : _testConnection,
                        child: Text(
                          strings.test_connection,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                _statusArea(),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://aistudio.google.com/apikey'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(strings.free_key),
                  ),
                ),
                IaSectionTitle(
                  Translations.of(context).ia_consent.settings_title,
                ),
                Text(Translations.of(context).ia_consent.settings_hint),
                const SizedBox(height: 8),
                for (final feature in AiFeature.values)
                  SwitchListTile(
                    key: ValueKey('ai-consent-${feature.name}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(aiFeatureName(context, feature)),
                    value: allowed.contains(feature),
                    // Allowing happens in the sheet that explains what is sent; only turning off is done here.
                    onChanged: allowed.contains(feature)
                        ? (_) => unawaited(_revoke(feature))
                        : null,
                  ),
                const SizedBox(height: 16),
                IaCard(
                  key: const ValueKey('ai-privacy'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.privacy_title,
                              style: textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(strings.privacy),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// The four providers as cards, two per row.
  Widget _providerGrid() {
    final strings = Translations.of(context).ia_settings;
    final options = [
      (AiProviderId.gemini, 'Gemini', Icons.auto_awesome_outlined),
      (AiProviderId.deepseek, 'DeepSeek', Icons.psychology_alt_outlined),
      (AiProviderId.openrouter, 'OpenRouter', Icons.alt_route_rounded),
      (AiProviderId.custom, strings.custom, Icons.tune_rounded),
    ];

    Widget card((AiProviderId, String, IconData) option) => Expanded(
      child: _ProviderCard(
        key: ValueKey('ai-provider-${option.$1.name}'),
        label: option.$2,
        icon: option.$3,
        selected: provider == option.$1,
        onTap: busy ? null : () => _selectProvider(option.$1),
      ),
    );

    return Column(
      children: [
        Row(
          children: [
            card(options[0]),
            const SizedBox(width: 12),
            card(options[1]),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            card(options[2]),
            const SizedBox(width: 12),
            card(options[3]),
          ],
        ),
      ],
    );
  }

  void _selectProvider(AiProviderId value) {
    final preset = aiPresets[value]!;
    setState(() {
      provider = value;
      url.text = preset.baseUrl;
      model.text = preset.model;
      status = null;
      hasKey = false;
      keyToConfirm = false;
    });
    unawaited(_refreshHasKey());
  }

  /// While testing: a spinner. After: a soft card that fades in, with the
  /// check of a successful connection popping once.
  Widget _statusArea() {
    final motion = BrandMotion.of(context);
    final text = status;

    final Widget content;
    if (busy) {
      content = const Padding(
        key: ValueKey('ai-testing'),
        padding: EdgeInsets.only(top: 16),
        child: LinearProgressIndicator(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      );
    } else if (text != null) {
      content = Padding(
        key: ValueKey('ai-status-$text'),
        padding: const EdgeInsets.only(top: 16),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: statusTone == IaTone.success ? 0.92 : 1, end: 1),
          duration: motion.card,
          curve: motion.bounce,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: IaNotice(tone: statusTone, text: text),
        ),
      );
    } else {
      content = const SizedBox.shrink(key: ValueKey('ai-no-status'));
    }

    return AnimatedSwitcher(
      duration: motion.state,
      switchInCurve: motion.enter,
      child: content,
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      child: IaCard(
        onTap: onTap,
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLowest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelDialog extends StatefulWidget {
  const _ModelDialog({required this.models});
  final List<String> models;
  @override
  State<_ModelDialog> createState() => _ModelDialogState();
}

class _ModelDialogState extends State<_ModelDialog> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final strings = Translations.of(context).ia_settings;
    final filtered = widget.models
        .where((id) => id.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text(strings.choose_model),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(labelText: strings.search),
              onChanged: (value) => setState(() => query = value),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(filtered[index]),
                  onTap: () => Navigator.pop(context, filtered[index]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
      ],
    );
  }
}
