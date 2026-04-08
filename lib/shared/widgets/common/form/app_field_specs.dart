import 'package:flutter/services.dart';

import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/brazilian_field_formatters.dart';
import 'package:plug_agente/shared/widgets/common/form/field_spec.dart';

/// Pre-built [FieldSpec] values for common Brazilian and generic field types.
///
/// Validators only enforce format/length for inline feedback; use
/// InputValidators and schemas on save for full domain rules.
abstract final class AppFieldSpecs {
  AppFieldSpecs._();

  static FieldSpec email(AppLocalizations l) => FieldSpec(
    keyboardType: TextInputType.emailAddress,
    validator: (String? value) => _validateEmail(value, l),
  );

  static FieldSpec url(AppLocalizations l) => FieldSpec(
    keyboardType: TextInputType.url,
    validator: (String? value) => _validateHttpUrl(value, l),
  );

  static FieldSpec cep(AppLocalizations l) => FieldSpec(
    formatters: BrazilianFieldFormatters.postalCode,
    keyboardType: TextInputType.number,
    hint: l.formHintCep,
    validator: (String? value) => _validateCep(value, l),
  );

  static FieldSpec phone(AppLocalizations l) => FieldSpec(
    formatters: BrazilianFieldFormatters.phone,
    keyboardType: TextInputType.phone,
    hint: l.formHintPhone,
    validator: (String? value) => _validatePhone(value, l),
  );

  static FieldSpec mobile(AppLocalizations l) => FieldSpec(
    formatters: BrazilianFieldFormatters.phone,
    keyboardType: TextInputType.phone,
    hint: l.formHintMobile,
    validator: (String? value) => _validateMobile(value, l),
  );

  static FieldSpec document(AppLocalizations l) => FieldSpec(
    formatters: BrazilianFieldFormatters.document,
    keyboardType: TextInputType.number,
    hint: l.formHintDocument,
    validator: (String? value) => _validateDocument(value, l),
  );

  static FieldSpec state(AppLocalizations l) => FieldSpec(
    formatters: BrazilianFieldFormatters.state,
    keyboardType: TextInputType.text,
    hint: l.formHintState,
    validator: (String? value) => _validateState(value, l),
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

  static String? _validateEmail(String? value, AppLocalizations l) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (!_emailPattern.hasMatch(trimmed)) {
      return l.formValidationEmailInvalid;
    }
    return null;
  }

  static String? _validateHttpUrl(String? value, AppLocalizations l) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return l.formValidationUrlHttpHttps;
    }
    return null;
  }

  static String? _validateCep(String? value, AppLocalizations l) {
    final digits = _digitsOnly(value);
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length != 8) {
      return l.formValidationCepDigits;
    }
    return null;
  }

  static String? _validatePhone(String? value, AppLocalizations l) {
    final digits = _digitsOnly(value);
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length != 10) {
      return l.formValidationPhoneDigits;
    }
    return null;
  }

  static String? _validateMobile(String? value, AppLocalizations l) {
    final digits = _digitsOnly(value);
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length != 11) {
      return l.formValidationMobileDigits;
    }
    if (digits.length > 2 && digits[2] != '9') {
      return l.formValidationMobileNineAfterDdd;
    }
    return null;
  }

  static String? _validateDocument(String? value, AppLocalizations l) {
    final digits = _digitsOnly(value);
    if (digits.isEmpty) {
      return null;
    }
    if (digits.length != 11 && digits.length != 14) {
      return l.formValidationDocumentDigits;
    }
    return null;
  }

  static String? _validateState(String? value, AppLocalizations l) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(trimmed)) {
      return l.formValidationStateLetters;
    }
    return null;
  }
}
