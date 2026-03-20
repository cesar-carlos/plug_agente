import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/theme/theme.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    super.key,
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
    this.readOnly = false,
    this.inputFormatters,
  });
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
  final bool readOnly;
  final List<TextInputFormatter>? inputFormatters;

  Widget? _buildPrefixIcon() {
    if (prefixIcon == null) return null;

    if (prefixIcon is Icon) {
      final icon = prefixIcon! as Icon;
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: Icon(icon.icon, size: 18, color: icon.color),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: prefixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    String? errorText;
    if (validator != null && controller != null && controller!.text.isNotEmpty) {
      errorText = validator!(controller!.text);
    }

    final textBox = TextBox(
      controller: controller,
      placeholder: hint,
      style: context.bodyText,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      readOnly: readOnly,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      suffix: suffixIcon,
      prefix: _buildPrefixIcon(),
    );

    if (errorText != null) {
      return InfoLabel(
        label: label,
        labelStyle: context.bodyStrong,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            textBox,
            const SizedBox(height: AppSpacing.xs),
            Text(
              errorText,
              style: context.bodyMuted.copyWith(
                color: AppColors.error,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return InfoLabel(
      label: label,
      labelStyle: context.bodyStrong,
      child: textBox,
    );
  }
}
