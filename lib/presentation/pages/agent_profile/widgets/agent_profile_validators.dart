import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/field_spec.dart';

String? requiredFieldValidator(AppLocalizations l10n, String label, String? value) {
  if ((value?.trim() ?? '').isEmpty) {
    return l10n.formFieldRequired(label);
  }
  return null;
}

String? requiredWithSpecValidator(
  AppLocalizations l10n,
  String label,
  FieldSpec fieldSpec,
  String? value,
) {
  final requiredError = requiredFieldValidator(l10n, label, value);
  if (requiredError != null) {
    return requiredError;
  }
  return fieldSpec.validator?.call(value);
}
