import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.enabled = true,
  });
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = widget.label ?? l10n.formFieldLabelPassword;
    return AppTextField(
      controller: widget.controller,
      label: label,
      hint: widget.hint ?? l10n.formPasswordDefaultHint,
      obscureText: _obscureText,
      validator:
          widget.validator ??
          (value) {
            if (value == null || value.trim().isEmpty) {
              return l10n.formPasswordRequired(label);
            }
            return null;
          },
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      prefixIcon: const Icon(FluentIcons.lock),
      suffixIcon: IconButton(
        icon: Icon(_obscureText ? FluentIcons.view : FluentIcons.hide),
        onPressed: () {
          setState(() {
            _obscureText = !_obscureText;
          });
        },
      ),
    );
  }
}
