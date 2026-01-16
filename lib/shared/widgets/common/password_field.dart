import 'package:fluent_ui/fluent_ui.dart';
import 'app_text_field.dart';

class PasswordField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  const PasswordField({
    super.key,
    this.label = 'Senha',
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint ?? 'Digite a senha',
      obscureText: _obscureText,
      validator: widget.validator ??
          (value) {
            if (value == null || value.trim().isEmpty) {
              return '${widget.label} é obrigatória';
            }
            return null;
          },
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      prefixIcon: const Icon(FluentIcons.lock),
      suffixIcon: IconButton(
        icon: Icon(
          _obscureText ? FluentIcons.view : FluentIcons.hide,
        ),
        onPressed: () {
          setState(() {
            _obscureText = !_obscureText;
          });
        },
      ),
    );
  }
}

