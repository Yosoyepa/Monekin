import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
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
  String? status;

  @override
  void initState() {
    super.initState();
    service = AiService.instance as AiServiceImpl;
    _load();
  }

  Future<void> _load() async {
    final config = await service.loadConfig();
    final savedKey = await service.hasKey(config);
    if (!mounted) return;
    setState(() {
      provider = config.provider;
      url.text = config.baseUrl;
      model.text = config.model;
      hasKey = savedKey;
      ready = true;
    });
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
    if (!mounted ||
        AiServiceImpl.keyNameFor(asked) != AiServiceImpl.keyNameFor(config)) {
      return;
    }
    setState(() => hasKey = saved);
  }

  Future<bool> _save() async {
    if (!isAllowedProviderUrl(config.baseUrl)) {
      setState(() {
        status = Translations.of(context).ia_settings.error_insecure_url;
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
    if (mounted) {
      setState(() {
        hasKey = savedKey;
        status = Translations.of(context).ia_settings.saved;
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
        status = Translations.of(context).ia_settings.key_deleted;
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
        setState(() => status = Translations.of(context).ia_settings.connected);
      }
    } on AiException catch (error) {
      if (mounted) setState(() => status = _error(error));
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
      if (mounted) setState(() => status = _error(error));
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
    return Scaffold(
      appBar: AppBar(title: Text(strings.title)),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<AiProviderId>(
                  initialValue: provider,
                  decoration: InputDecoration(labelText: strings.provider),
                  items: [
                    const DropdownMenuItem(
                      value: AiProviderId.gemini,
                      child: Text('Gemini'),
                    ),
                    const DropdownMenuItem(
                      value: AiProviderId.deepseek,
                      child: Text('DeepSeek'),
                    ),
                    const DropdownMenuItem(
                      value: AiProviderId.openrouter,
                      child: Text('OpenRouter'),
                    ),
                    DropdownMenuItem(
                      value: AiProviderId.custom,
                      child: Text(strings.custom),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          final preset = aiPresets[value]!;
                          setState(() {
                            provider = value;
                            url.text = preset.baseUrl;
                            model.text = preset.model;
                            status = null;
                            hasKey = false;
                          });
                          unawaited(_refreshHasKey());
                        },
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('ai-url'),
                  controller: url,
                  readOnly: provider != AiProviderId.custom,
                  decoration: InputDecoration(labelText: strings.base_url),
                  onChanged: (_) {
                    setState(() => hasKey = false);
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
                    helperText: hasKey ? null : strings.key_per_destination,
                    helperMaxLines: 3,
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('ai-save'),
                      onPressed: busy ? null : _save,
                      child: Text(strings.save),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : _testConnection,
                      child: Text(strings.test_connection),
                    ),
                    TextButton(
                      key: const ValueKey('ai-delete'),
                      onPressed: busy ? null : _delete,
                      child: Text(strings.delete_key),
                    ),
                  ],
                ),
                if (busy) const LinearProgressIndicator(),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(status!),
                  ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://aistudio.google.com/apikey'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(strings.free_key),
                ),
                Text(strings.privacy),
              ],
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
