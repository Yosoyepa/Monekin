import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:monekin/features_ia/core/catalog/ai_catalog.dart';
import 'package:monekin/features_ia/inbox/inbox_navigation.dart';
import 'package:monekin/features_ia/statements/statement_importer.dart';
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
      final result =
          (pdf ? null : importer.parseCsv(text, account!)) ??
          await importer.parseWithAi(text, account!);
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

  @override
  Widget build(BuildContext context) {
    final strings = Translations.of(context).ia_statements;
    return Scaffold(
      appBar: AppBar(title: Text(strings.title)),
      body: FutureBuilder<AiCatalog>(
        future: catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(strings.catalog_error));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : choose,
                icon: const Icon(Icons.attach_file),
                label: Text(file?.name ?? strings.choose_file),
              ),
              TextField(
                controller: label,
                enabled: !busy,
                decoration: InputDecoration(labelText: strings.label),
                onChanged: (_) => setState(() {}),
              ),
              DropdownButtonFormField<String>(
                initialValue: account,
                decoration: InputDecoration(labelText: strings.account),
                items: [
                  for (final item in snapshot.data!.accounts)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => account = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed:
                    busy ||
                        file == null ||
                        account == null ||
                        label.text.trim().isEmpty
                    ? null
                    : importFile,
                child: busy
                    ? const CircularProgressIndicator()
                    : Text(strings.import),
              ),
            ],
          );
        },
      ),
    );
  }
}
