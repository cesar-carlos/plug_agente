import 'package:flutter/services.dart';

/// Bundles optional formatting and lightweight UI validation for AppTextField.
///
/// Domain validation (e.g. full CPF/CNPJ checksum) stays in application layer.
class FieldSpec {
  const FieldSpec({
    this.formatters = const <TextInputFormatter>[],
    this.validator,
    this.keyboardType,
    this.hint,
  });

  final List<TextInputFormatter> formatters;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final String? hint;

  FieldSpec merge(FieldSpec other) {
    return FieldSpec(
      formatters: <TextInputFormatter>[...formatters, ...other.formatters],
      validator: other.validator ?? validator,
      keyboardType: other.keyboardType ?? keyboardType,
      hint: other.hint ?? hint,
    );
  }
}
