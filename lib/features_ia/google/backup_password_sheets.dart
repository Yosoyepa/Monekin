// Sheets that ask for the backup password (T002, round 3): creating or changing it,
// and typing it to restore an encrypted copy.
import 'package:flutter/material.dart';
import 'package:monekin/features_ia/google/backup_password.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// Asks for a new password twice. Returns it, or null when dismissed.
Future<String?> showCreateBackupPasswordSheet(
  BuildContext context, {
  bool change = false,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => CreateBackupPasswordSheet(change: change),
);

/// Asks for the password a copy was made with. Returns it, or null when dismissed.
Future<String?> showRestorePasswordSheet(
  BuildContext context, {
  bool wrongBefore = false,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => RestorePasswordSheet(wrongBefore: wrongBefore),
);

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
    required this.onChanged,
    this.errorText,
    this.autofocus = false,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_google;

    return TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: obscure ? t.pw_show : t.pw_hide,
          icon: Icon(
            obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _ForgetWarning extends StatelessWidget {
  const _ForgetWarning();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                Translations.of(context).ia_google.pw_warning,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_google;
    final scheme = Theme.of(context).colorScheme;
    final strength = backupPasswordStrength(password);

    final (value, label, color) = switch (strength) {
      BackupPasswordStrength.weak => (1 / 3, t.pw_strength_weak, scheme.error),
      BackupPasswordStrength.fair => (
        2 / 3,
        t.pw_strength_fair,
        scheme.tertiary,
      ),
      BackupPasswordStrength.strong => (
        1.0,
        t.pw_strength_strong,
        scheme.primary,
      ),
    };

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: password.isEmpty ? 0 : value,
              minHeight: 6,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          password.isEmpty ? '' : label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class CreateBackupPasswordSheet extends StatefulWidget {
  const CreateBackupPasswordSheet({super.key, this.change = false});

  /// Changing an existing password: tells that older copies keep the old one.
  final bool change;

  @override
  State<CreateBackupPasswordSheet> createState() =>
      _CreateBackupPasswordSheetState();
}

class _CreateBackupPasswordSheetState extends State<CreateBackupPasswordSheet> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _mismatch =>
      _confirm.text.isNotEmpty && _confirm.text != _password.text;

  bool get _canSave =>
      isValidBackupPassword(_password.text) && _confirm.text == _password.text;

  void _save() {
    if (_canSave) Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_google;
    final text = Theme.of(context).textTheme;

    return _SheetBody(
      children: [
        Text(
          widget.change ? t.pw_change_title : t.pw_create_title,
          style: text.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(t.pw_encrypted_note, style: text.bodyMedium),
        const SizedBox(height: 16),
        const _ForgetWarning(),
        if (widget.change) ...[
          const SizedBox(height: 12),
          Text(t.pw_change_note, style: text.bodyMedium),
        ],
        const SizedBox(height: 16),
        _PasswordField(
          controller: _password,
          label: t.pw_label,
          obscure: _obscure,
          onToggle: () => setState(() => _obscure = !_obscure),
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        Text(
          t.pw_min_length(n: kMinBackupPasswordLength),
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        _StrengthMeter(password: _password.text),
        const SizedBox(height: 16),
        _PasswordField(
          controller: _confirm,
          label: t.pw_confirm_label,
          obscure: _obscure,
          onToggle: () => setState(() => _obscure = !_obscure),
          onChanged: (_) => setState(() {}),
          errorText: _mismatch ? t.pw_mismatch : null,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(t.pw_save),
        ),
      ],
    );
  }
}

class RestorePasswordSheet extends StatefulWidget {
  const RestorePasswordSheet({super.key, this.wrongBefore = false});

  /// The password typed before was not the right one.
  final bool wrongBefore;

  @override
  State<RestorePasswordSheet> createState() => _RestorePasswordSheetState();
}

class _RestorePasswordSheetState extends State<RestorePasswordSheet> {
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isNotEmpty) Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).ia_google;
    final text = Theme.of(context).textTheme;

    return _SheetBody(
      children: [
        Text(t.restore_pw_title, style: text.titleLarge),
        const SizedBox(height: 8),
        Text(t.restore_pw_descr, style: text.bodyMedium),
        const SizedBox(height: 16),
        _PasswordField(
          controller: _password,
          label: t.pw_label,
          obscure: _obscure,
          autofocus: true,
          onToggle: () => setState(() => _obscure = !_obscure),
          onChanged: (_) => setState(() {}),
          errorText: widget.wrongBefore ? t.restore_pw_wrong : null,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _password.text.isEmpty ? null : _submit,
          child: Text(t.restore),
        ),
      ],
    );
  }
}
