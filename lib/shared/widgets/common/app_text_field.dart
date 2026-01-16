import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? initialValue;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.initialValue,
    this.validator,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.suffixIcon,
    this.prefixIcon,
    this.enabled = true,
    this.inputFormatters,
  });

  Widget? _buildPrefixIcon() {
    if (prefixIcon == null) return null;

    if (prefixIcon is Icon) {
      final icon = prefixIcon as Icon;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Icon(icon.icon, size: 18, color: icon.color),
      );
    }

    return Padding(padding: const EdgeInsets.only(left: 8), child: prefixIcon);
  }

  @override
  Widget build(BuildContext context) {
    String? errorText;
    if (validator != null &&
        controller != null &&
        controller!.text.isNotEmpty) {
      errorText = validator!(controller!.text);
    }

    final textBox = TextBox(
      controller: controller,
      placeholder: hint,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      suffix: suffixIcon,
      prefix: _buildPrefixIcon(),
    );

    if (errorText != null) {
      return InfoLabel(
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            textBox,
            const SizedBox(height: 4),
            Text(
              errorText,
              style: FluentTheme.of(context).typography.caption?.copyWith(
                    color: const Color(0xFFD13438), // Error color
                  ),
            ),
          ],
        ),
      );
    }

    return InfoLabel(label: label, child: textBox);
  }
}
