import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import 'package:plug_agente/shared/widgets/common/app_text_field.dart';

class NumericField extends StatelessWidget {
  const NumericField({
    required this.label,
    super.key,
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.prefixIcon,
    this.minValue,
    this.maxValue,
  });
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final IconData? prefixIcon;
  final int? minValue;
  final int? maxValue;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      hint: hint,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator:
          validator ??
          (value) {
            if (value == null || value.trim().isEmpty) {
              return '$label é obrigatório';
            }
            final number = int.tryParse(value);
            if (number == null) {
              return 'Valor inválido';
            }
            if (minValue != null && number < minValue!) {
              return 'Valor mínimo: $minValue';
            }
            if (maxValue != null && number > maxValue!) {
              return 'Valor máximo: $maxValue';
            }
            return null;
          },
      onChanged: onChanged,
      enabled: enabled,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
    );
  }
}
