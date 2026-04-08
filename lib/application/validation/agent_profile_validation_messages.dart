/// User-facing strings for agent profile (Zard) validation.
///
/// For UI, build from `AppLocalizations` using
/// `agentProfileValidationMessages` in `presentation/mappers/`.
/// Use [english] for RPC and tests.
class AgentProfileValidationMessages {
  AgentProfileValidationMessages({
    required this.labelName,
    required this.labelTradeName,
    required this.labelStreet,
    required this.labelAddressNumber,
    required this.labelDistrict,
    required this.labelPostalCode,
    required this.labelCity,
    required this.labelState,
    required this.labelPhone,
    required this.labelMobile,
    required this.labelEmail,
    required this.labelNotes,
    required this.requiredField,
    required this.maxLengthField,
    required this.notesMaxLength,
    required this.documentInvalid,
    required this.postalCodeInvalid,
    required this.phoneInvalid,
    required this.mobileInvalid,
    required this.emailInvalid,
    required this.documentTypeMismatch,
    required this.documentTypeEnum,
    required this.stateInvalid,
  });

  final String labelName;
  final String labelTradeName;
  final String labelStreet;
  final String labelAddressNumber;
  final String labelDistrict;
  final String labelPostalCode;
  final String labelCity;
  final String labelState;
  final String labelPhone;
  final String labelMobile;
  final String labelEmail;
  final String labelNotes;

  final String Function(String fieldLabel) requiredField;
  final String Function(String fieldLabel, int maxLength) maxLengthField;
  final String Function(int max) notesMaxLength;

  final String documentInvalid;
  final String postalCodeInvalid;
  final String phoneInvalid;
  final String mobileInvalid;
  final String emailInvalid;
  final String documentTypeMismatch;
  final String documentTypeEnum;
  final String stateInvalid;

  /// Default messages for hub/RPC and tests (English).
  static final AgentProfileValidationMessages english = AgentProfileValidationMessages(
    labelName: 'Name',
    labelTradeName: 'Trade name',
    labelStreet: 'Street address',
    labelAddressNumber: 'Number',
    labelDistrict: 'District',
    labelPostalCode: 'Postal code',
    labelCity: 'City',
    labelState: 'State',
    labelPhone: 'Phone',
    labelMobile: 'Mobile',
    labelEmail: 'Email',
    labelNotes: 'Note',
    requiredField: (String fieldLabel) => '$fieldLabel is required.',
    maxLengthField: (String fieldLabel, int maxLength) =>
        '$fieldLabel must be at most $maxLength characters.',
    notesMaxLength: (int max) => 'Note must be at most $max characters.',
    documentInvalid: 'Invalid CPF/CNPJ.',
    postalCodeInvalid: 'Invalid postal code. Enter 8 digits.',
    phoneInvalid: 'Invalid phone number.',
    mobileInvalid: 'Invalid mobile number.',
    emailInvalid: 'Invalid email address.',
    documentTypeMismatch: 'Document type does not match the CPF/CNPJ entered.',
    documentTypeEnum: 'Document type must be cpf or cnpj.',
    stateInvalid: 'State must be exactly 2 letters.',
  );
}
