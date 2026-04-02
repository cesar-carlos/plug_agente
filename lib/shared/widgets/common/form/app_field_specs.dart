import 'package:flutter/services.dart';

import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/shared/widgets/common/form/brazilian_field_formatters.dart';
import 'package:plug_agente/shared/widgets/common/form/field_spec.dart';

/// Pre-built FieldSpec values for common Brazilian and generic field types.
///
/// Validators only enforce format/length for inline feedback; use
/// InputValidators and schemas on save for full domain rules.
abstract final class AppFieldSpecs {
  AppFieldSpecs._();

  // ignore: prefer_const_constructors — validator tear-offs are not const.
  static final FieldSpec email = FieldSpec(
    keyboardType: TextInputType.emailAddress,
    validator: _validateEmail,
  );

  // ignore: prefer_const_constructors — validator tear-offs are not const.
  static final FieldSpec url = FieldSpec(
    keyboardType: TextInputType.url,
    validator: _validateHttpUrl,
  );

  static final FieldSpec cep = FieldSpec(
    formatters: BrazilianFieldFormatters.postalCode,
    keyboardType: TextInputType.number,
    hint: AppStrings.formHintCep,
    validator: _validateCep,
  );

  static final FieldSpec phone = FieldSpec(
    formatters: BrazilianFieldFormatters.phone,
    keyboardType: TextInputType.phone,
    hint: AppStrings.formHintPhone,
    validator: _validatePhone,
  );

  static final FieldSpec mobile = FieldSpec(
    formatters: BrazilianFieldFormatters.phone,
    keyboardType: TextInputType.phone,
    hint: AppStrings.formHintMobile,
    validator: _validateMobile,
  );

  static final FieldSpec document = FieldSpec(
    formatters: BrazilianFieldFormatters.document,
    keyboardType: TextInputType.number,
    hint: AppStrings.formHintDocument,
    validator: _validateDocument,
  );

  static final FieldSpec state = FieldSpec(
    formatters: BrazilianFieldFormatters.state,
    keyboardType: TextInputType.text,
    hint: AppStrings.formHintState,
    validator: _validateState,
  );

  static final RegExp _emailPattern = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  static String _digitsOnly(String? value) {
    if (value == null) {
      return '';
    }
    return value.replaceAll(RegExp('[^0-9]'), '');
  }

  static String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (!_emailPattern.hasMatch(trimmed)) {
      return AppStrings.formValidationEmailInvalid;
    }
    return null;
  }

  static String? _validateHttpUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return AppStrings.formValidationUrlHttpHttps;
    }
    return null;
  }

  static String? _validateCep(String? value) {
    final digits = _digitsOnly(value);
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length != 8) {
      return AppStrings.formValidationCepDigits;
    }
    return null;
  }

  static String? _validatePhone(String? value) {
    final digits = _digitsOnly(value);
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length != 10) {
      return AppStrings.formValidationPhoneDigits;
    }
    return null;
  }

  static String? _validateMobile(String? value) {
    final digits = _digitsOnly(value);
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length != 11) {
      return AppStrings.formValidationMobileDigits;
    }
    if (digits.length > 2 && digits[2] != '9') {
      return AppStrings.formValidationMobileNineAfterDdd;
    }
    return null;
  }

  static String? _validateDocument(String? value) {
    final digits = _digitsOnly(value);
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length != 11 && digits.length != 14) {
      return AppStrings.formValidationDocumentDigits;
    }
    return null;
  }

  static String? _validateState(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(trimmed)) {
      return AppStrings.formValidationStateLetters;
    }
    return null;
  }
}
