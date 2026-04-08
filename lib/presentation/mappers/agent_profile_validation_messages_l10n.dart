import 'package:plug_agente/application/validation/agent_profile_validation_messages.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

AgentProfileValidationMessages agentProfileValidationMessages(AppLocalizations l) {
  return AgentProfileValidationMessages(
    labelName: l.agentProfileFieldName,
    labelTradeName: l.agentProfileFieldTradeName,
    labelStreet: l.agentProfileFieldStreet,
    labelAddressNumber: l.agentProfileFieldNumber,
    labelDistrict: l.agentProfileFieldDistrict,
    labelPostalCode: l.agentProfileFieldPostalCode,
    labelCity: l.agentProfileFieldCity,
    labelState: l.agentProfileFieldState,
    labelPhone: l.agentProfileFieldPhone,
    labelMobile: l.agentProfileFieldMobile,
    labelEmail: l.agentProfileFieldEmail,
    labelNotes: l.agentProfileFieldNotes,
    requiredField: l.formFieldRequired,
    maxLengthField: l.agentProfileValidationMaxLength,
    notesMaxLength: l.agentProfileValidationNotesMaxLength,
    documentInvalid: l.agentProfileValidationDocumentInvalid,
    postalCodeInvalid: l.agentProfileValidationPostalCodeInvalid,
    phoneInvalid: l.agentProfileValidationPhoneInvalid,
    mobileInvalid: l.agentProfileValidationMobileInvalid,
    emailInvalid: l.agentProfileValidationEmailInvalid,
    documentTypeMismatch: l.agentProfileValidationDocumentTypeMismatch,
    documentTypeEnum: l.agentProfileValidationDocumentTypeEnum,
    stateInvalid: l.agentProfileValidationStateInvalid,
  );
}
