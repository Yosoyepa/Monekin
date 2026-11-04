// The sheet that asks, once per function, what the AI will receive (T002, round 3). Owner: f3-consent.
import 'package:flutter/material.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/consent/ai_consent.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// Short name of the provider as the user knows it, and the host the data goes to.
({String provider, String host}) aiDestinationLabels(
  AiProviderConfig config,
  String customLabel,
) {
  final host = Uri.tryParse(config.baseUrl.trim())?.host ?? '';
  final provider = switch (config.provider) {
    AiProviderId.gemini => 'Gemini',
    AiProviderId.deepseek => 'DeepSeek',
    AiProviderId.openrouter => 'OpenRouter',
    AiProviderId.custom => customLabel,
  };
  return (provider: provider, host: host);
}

/// Name of [feature] in the settings and in the sheet.
String aiFeatureName(BuildContext context, AiFeature feature) {
  final t = Translations.of(context).ia_consent;
  return switch (feature) {
    AiFeature.receipt => t.feature_receipt,
    AiFeature.statement => t.feature_statement,
    AiFeature.notice => t.feature_notice,
    AiFeature.insights => t.feature_insights,
    AiFeature.recategorize => t.feature_recategorize,
  };
}

/// Asks the user to allow [feature] unless that was already done for the destination in use.
/// True when the function may go on.
Future<bool> ensureAiConsent(BuildContext context, AiFeature feature) async {
  final config = await currentAiConfig();
  if (await AiConsent.instance.isGranted(feature, config)) return true;
  if (!context.mounted) return false;
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => AiConsentSheet(feature: feature, config: config),
  );
  if (accepted != true) return false;
  await AiConsent.instance.grant(feature, config);
  return true;
}

const _monospace = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Consolas', 'Courier New'],
  fontSize: 12,
);

/// Shows [text], the exact message of a function, scrollable and in monospace.
Future<void> showAiSentDialog(BuildContext context, {required String text}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.ia_consent.sent_title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            key: const Key('sent-text'),
            style: _monospace,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.ia_consent.close),
        ),
      ],
    ),
  );
}

/// Shows the exact [text] about to leave the phone and asks to send it. True only when the user sends it.
Future<bool> confirmAiText(
  BuildContext context, {
  required String text,
  required AiProviderConfig config,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => AiPreviewSheet(text: text, config: config),
  );
  return sent == true;
}

/// The text that will be sent, already reduced and masked, with «Send» and «Cancel».
class AiPreviewSheet extends StatelessWidget {
  const AiPreviewSheet({super.key, required this.text, required this.config});

  final String text;
  final AiProviderConfig config;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_consent;
    final textTheme = Theme.of(context).textTheme;
    final labels = aiDestinationLabels(config, t.custom_provider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BrandTokens.pageMargin,
        0,
        BrandTokens.pageMargin,
        BrandTokens.pageMargin,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.preview_title, style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(t.preview_hint(provider: labels.provider)),
          const SizedBox(height: 12),
          Flexible(
            child: IaCard(
              key: const Key('preview-card'),
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    text,
                    key: const Key('preview-text'),
                    style: _monospace,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('preview-send'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.preview_send(provider: labels.provider)),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('preview-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
        ],
      ),
    );
  }
}

class AiConsentSheet extends StatelessWidget {
  const AiConsentSheet({
    super.key,
    required this.feature,
    required this.config,
  });

  final AiFeature feature;
  final AiProviderConfig config;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_consent;
    final textTheme = Theme.of(context).textTheme;
    final labels = aiDestinationLabels(config, t.custom_provider);
    final sent = switch (feature) {
      AiFeature.receipt => t.sent_receipt,
      AiFeature.statement => t.sent_statement,
      AiFeature.notice => t.sent_notice,
      AiFeature.insights => t.sent_insights,
      AiFeature.recategorize => t.sent_recategorize,
    };

    Widget block(IconData icon, String title, String body, {Key? key}) =>
        IaCard(
          key: key,
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(body),
                  ],
                ),
              ),
            ],
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        BrandTokens.pageMargin,
        0,
        BrandTokens.pageMargin,
        BrandTokens.pageMargin,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.sheet_title(feature: aiFeatureName(context, feature)),
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          block(
            Icons.upload_rounded,
            t.what_is_sent,
            sent,
            key: const Key('consent-sent'),
          ),
          block(
            Icons.dns_outlined,
            t.sent_to,
            t.destination(provider: labels.provider, host: labels.host),
            key: const Key('consent-destination'),
          ),
          block(
            Icons.block_rounded,
            t.never_sent,
            t.never_sent_body,
            key: const Key('consent-never'),
          ),
          const SizedBox(height: 4),
          FilledButton(
            key: const Key('consent-accept'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.accept),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('consent-decline'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.decline),
          ),
        ],
      ),
    );
  }
}
