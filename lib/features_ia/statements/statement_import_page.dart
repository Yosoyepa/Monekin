import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/core/privacy/picker_copy.dart';
import 'package:monekin/features_ia/inbox/inbox_navigation.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';
import 'package:monekin/features_ia/ui/ia_ui.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class StatementImportPage extends StatefulWidget {
  const StatementImportPage({super.key});
  @override
  State<StatementImportPage> createState() => _StatementImportPageState();
}

class _StatementImportPageState extends State<StatementImportPage> {
  final importer = StatementImporter();
  final label = TextEditingController();
  late Future<AiCatalog> catalog;
  PlatformFile? file;
  String? account;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    catalog = importer.catalogLoader();
  }

  @override
  void dispose() {
    label.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'pdf'],
      withData: true,
    );
    if (!mounted || selection == null) return;
    setState(() {
      file = selection.files.single;
      if (label.text.isEmpty) {
        label.text = file!.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  Future<void> importFile() async {
    final selected = file;
    if (selected?.bytes == null ||
        account == null ||
        label.text.trim().isEmpty) {
      return;
    }
    setState(() => busy = true);
    final strings = Translations.of(context).ia_statements;
    try {
      final pdf = selected!.extension?.toLowerCase() == 'pdf';
      final text = pdf
          ? await importer.extractPdf(selected.bytes!)
          : importer.decodeText(selected.bytes!);
      final parsed = pdf ? null : importer.parseCsv(text, account!);
      final interpreted = parsed ?? await importer.parseWithAi(text, account!);
      final result = await importer.proposeCategories(interpreted);
      if (result.categoryWarning && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.categories_warning)));
      }
      final difference = result.difference;
      final note = difference == null
          ? strings.balance_missing
          : strings.reconciliation(
              net: result.net.toStringAsFixed(2),
              difference: difference.toStringAsFixed(2),
            );
      final id = await importer.save(
        result: result,
        label: label.text.trim(),
        text: text,
        note: note,
      );
      await deletePickerCopy(selected.path);
      if (!mounted) return;
      await openInboxReview(context, id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.import_error)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool get _ready =>
      file != null && account != null && label.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final strings = Translations.of(context).ia_statements;
    return Scaffold(
      appBar: AppBar(title: Text(strings.title)),
      body: FutureBuilder<AiCatalog>(
        future: catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return IaStatusView(
              mood: ChanchiMood.worried,
              title: strings.catalog_error,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (busy) {
            return IaStatusView(
              key: const Key('statement-reading'),
              mood: ChanchiMood.thinking,
              title: strings.reading,
              message: strings.categories_disclosure,
            );
          }
          return _steps(context, snapshot.data!);
        },
      ),
    );
  }

  Widget _steps(BuildContext context, AiCatalog data) {
    final strings = Translations.of(context).ia_statements;
    final motion = BrandMotion.of(context);
    final accountName = data.accounts
        .where((item) => item.id == account)
        .map((item) => item.name)
        .firstOrNull;
    final filled = file != null;
    final named = filled && account != null && label.text.trim().isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        BrandTokens.pageMargin,
        8,
        BrandTokens.pageMargin,
        32,
      ),
      children: [
        _StepCard(
          number: 1,
          title: strings.step_file,
          done: filled,
          child: OutlinedButton.icon(
            key: const Key('statement-choose'),
            onPressed: choose,
            icon: const Icon(Icons.attach_file),
            label: Text(
              file?.name ?? strings.choose_file,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedOpacity(
          opacity: filled ? 1 : 0.5,
          duration: motion.state,
          child: IgnorePointer(
            ignoring: !filled,
            child: _StepCard(
              number: 2,
              title: strings.step_account,
              done: named,
              child: Column(
                children: [
                  TextField(
                    controller: label,
                    decoration: InputDecoration(labelText: strings.label),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: account,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: strings.account),
                    items: [
                      for (final item in data.accounts)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => account = value),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedOpacity(
          opacity: named ? 1 : 0.5,
          duration: motion.state,
          child: IgnorePointer(
            ignoring: !named,
            child: _StepCard(
              number: 3,
              title: strings.step_preview,
              done: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _previewRow(strings.preview_file, file?.name),
                  _previewRow(strings.preview_label, label.text.trim()),
                  _previewRow(strings.preview_account, accountName),
                  const SizedBox(height: 12),
                  IaNotice(
                    key: const Key('statement-privacy'),
                    tone: IaTone.info,
                    icon: Icons.lock_outline_rounded,
                    text: strings.categories_disclosure,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('statement-import'),
                      onPressed: _ready ? importFile : null,
                      child: Text(strings.import),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewRow(String name, String? value) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              name,
              style: textTheme.bodySmall?.copyWith(
                color: BrandColors.of(context).textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value == null || value.isEmpty ? '—' : value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A numbered step; the number turns into a check once it is done.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.done,
    required this.child,
  });

  final int number;
  final String title;
  final bool done;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final motion = BrandMotion.of(context);

    return IaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: motion.state,
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? BrandColors.of(context).income : scheme.primary,
                ),
                child: done
                    ? Icon(Icons.check_rounded, size: 18, color: scheme.surface)
                    : Text(
                        '$number',
                        style: textTheme.labelLarge?.copyWith(
                          color: scheme.onPrimary,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
