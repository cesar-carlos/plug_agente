import 'package:plug_agente/application/validation/agent_profile_validation_messages.dart';
import 'package:plug_agente/application/validation/zard_adapter.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:result_dart/result_dart.dart';
import 'package:zard/zard.dart';

class AgentProfileAddress {
  const AgentProfileAddress({
    required this.street,
    required this.number,
    required this.district,
    required this.postalCode,
    required this.city,
    required this.state,
  });

  factory AgentProfileAddress.fromMap(Map<String, dynamic> json) {
    return AgentProfileAddress(
      street: json['street'] as String,
      number: json['number'] as String,
      district: json['district'] as String,
      postalCode: json['postal_code'] as String,
      city: json['city'] as String,
      state: json['state'] as String,
    );
  }

  final String street;
  final String number;
  final String district;
  final String postalCode;
  final String city;
  final String state;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'street': street,
      'number': number,
      'district': district,
      'postal_code': postalCode,
      'city': city,
      'state': state,
    };
  }
}

class AgentProfile {
  const AgentProfile({
    required this.name,
    required this.tradeName,
    required this.document,
    required this.documentType,
    required this.mobile,
    required this.email,
    required this.address,
    this.phone,
    this.notes,
  });

  factory AgentProfile.fromMap(Map<String, dynamic> json) {
    return AgentProfile(
      name: json['name'] as String,
      tradeName: json['trade_name'] as String,
      document: json['document'] as String,
      documentType: json['document_type'] as String,
      phone: json['phone'] as String?,
      mobile: json['mobile'] as String,
      email: json['email'] as String,
      address: AgentProfileAddress.fromMap(
        json['address'] as Map<String, dynamic>,
      ),
      notes: json['notes'] as String?,
    );
  }

  static final RegExp _digitsOnlyPattern = RegExp(r'^\d+$');
  static final RegExp _nonDigitsPattern = RegExp('[^0-9]');
  static final RegExp _statePattern = RegExp(r'^[A-Z]{2}$');

  static Schema<Map<String, dynamic>>? _englishProfileSchema;

  static Schema<Map<String, dynamic>> _profileSchemaFor(AgentProfileValidationMessages messages) {
    if (identical(messages, AgentProfileValidationMessages.english)) {
      return _englishProfileSchema ??= _buildProfileSchema(messages);
    }
    return _buildProfileSchema(messages);
  }

  static Schema<Map<String, dynamic>> _buildProfileSchema(AgentProfileValidationMessages m) {
    final addressSchema = z
        .interface(<String, Schema<dynamic>>{
          'street': _requiredText(m, m.labelStreet, 100),
          'number': _requiredText(m, m.labelAddressNumber, 15),
          'district': _requiredText(m, m.labelDistrict, 60),
          'postal_code': _postalCodeSchema(m),
          'city': _requiredText(m, m.labelCity, 60),
          'state': z.string().trim().toUpperCase().refine(
            _statePattern.hasMatch,
            message: m.stateInvalid,
          ),
        })
        .strict();

    return z
        .interface(<String, Schema<dynamic>>{
          'name': _requiredText(m, m.labelName, 100),
          'trade_name': _requiredText(m, m.labelTradeName, 100),
          'document': _documentSchema(m),
          'document_type': z.$enum(
            const <String>['cpf', 'cnpj'],
            message: m.documentTypeEnum,
          ),
          'phone?': _phoneSchema(m),
          'mobile': _mobileSchema(m),
          'email': z.string().trim().toLowerCase().email(
            pattern: z.regexes.email,
            message: m.emailInvalid,
          ),
          'address': addressSchema,
          'notes?': z.string().trim().max(
            2000,
            message: m.notesMaxLength(2000),
          ),
        })
        .strict()
        .refine(
          (Map<String, dynamic> value) =>
              value['document_type'] == _resolveDocumentType(value['document'] as String),
          message: m.documentTypeMismatch,
        );
  }

  final String name;
  final String tradeName;
  final String document;
  final String documentType;
  final String? phone;
  final String mobile;
  final String email;
  final AgentProfileAddress address;
  final String? notes;

  static Result<AgentProfile> fromFormFields({
    required String name,
    required String tradeName,
    required String document,
    required String phone,
    required String mobile,
    required String email,
    required String street,
    required String number,
    required String district,
    required String postalCode,
    required String city,
    required String state,
    required String notes,
    required AgentProfileValidationMessages validationMessages,
  }) {
    final normalizedDocument = _digitsOnly(document);

    return _parseProfile(
      <String, dynamic>{
        'name': name,
        'trade_name': tradeName,
        'document': document,
        'document_type': _resolveDocumentType(normalizedDocument),
        if (phone.trim().isNotEmpty) 'phone': phone,
        'mobile': mobile,
        'email': email,
        'address': <String, dynamic>{
          'street': street,
          'number': number,
          'district': district,
          'postal_code': postalCode,
          'city': city,
          'state': state,
        },
        if (notes.trim().isNotEmpty) 'notes': notes,
      },
      validationMessages,
    );
  }

  static Result<AgentProfile> fromConfig(
    Config config, {
    AgentProfileValidationMessages? validationMessages,
  }) {
    final m = validationMessages ?? AgentProfileValidationMessages.english;
    final normalizedDocument = _digitsOnly(config.cnaeCnpjCpf);

    return _parseProfile(
      <String, dynamic>{
        'name': config.nome,
        'trade_name': config.nomeFantasia,
        'document': normalizedDocument,
        'document_type': _resolveDocumentType(normalizedDocument),
        if (config.telefone.trim().isNotEmpty) 'phone': config.telefone,
        'mobile': config.celular,
        'email': config.email,
        'address': <String, dynamic>{
          'street': config.endereco,
          'number': config.numeroEndereco,
          'district': config.bairro,
          'postal_code': config.cep,
          'city': config.nomeMunicipio,
          'state': config.ufMunicipio,
        },
        if (config.observacao.trim().isNotEmpty) 'notes': config.observacao,
      },
      m,
    );
  }

  static Result<AgentProfile> fromRpcPayload(
    dynamic payload, {
    AgentProfileValidationMessages? validationMessages,
  }) {
    final m = validationMessages ?? AgentProfileValidationMessages.english;
    return _parseProfile(payload, m);
  }

  Config applyToConfig(Config config) {
    return config.copyWith(
      nome: name,
      nomeFantasia: tradeName,
      cnaeCnpjCpf: document,
      telefone: phone ?? '',
      celular: mobile,
      email: email,
      endereco: address.street,
      numeroEndereco: address.number,
      bairro: address.district,
      cep: address.postalCode,
      nomeMunicipio: address.city,
      ufMunicipio: address.state,
      observacao: notes ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'trade_name': tradeName,
      'document': document,
      'document_type': documentType,
      if (phone != null && phone!.isNotEmpty) 'phone': phone,
      'mobile': mobile,
      'email': email,
      'address': address.toJson(),
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }

  static Schema<String> _requiredText(
    AgentProfileValidationMessages m,
    String label,
    int maxLength,
  ) {
    return z
        .string()
        .trim()
        .min(1, message: m.requiredField(label))
        .max(
          maxLength,
          message: m.maxLengthField(label, maxLength),
        );
  }

  static Schema<String> _documentSchema(AgentProfileValidationMessages m) {
    return z
        .string()
        .trim()
        .refine(
          _isValidCpfOrCnpj,
          message: m.documentInvalid,
        )
        .transformTyped(_digitsOnly);
  }

  static Schema<String> _postalCodeSchema(AgentProfileValidationMessages m) {
    return z
        .string()
        .trim()
        .refine(
          (String value) {
            final digits = _digitsOnly(value);
            return digits.length == 8 && _digitsOnlyPattern.hasMatch(digits);
          },
          message: m.postalCodeInvalid,
        )
        .transformTyped(_digitsOnly);
  }

  static Schema<String> _phoneSchema(AgentProfileValidationMessages m) {
    return z
        .string()
        .trim()
        .refine(
          (String value) {
            final digits = _digitsOnly(value);
            return digits.length == 10 && _digitsOnlyPattern.hasMatch(digits);
          },
          message: m.phoneInvalid,
        )
        .transformTyped(_digitsOnly);
  }

  static Schema<String> _mobileSchema(AgentProfileValidationMessages m) {
    return z
        .string()
        .trim()
        .refine(
          (String value) {
            final digits = _digitsOnly(value);
            final hasValidLength = digits.length == 11 && _digitsOnlyPattern.hasMatch(digits);
            final startsWithNine = digits.length == 11 && digits.length > 2 && digits[2] == '9';
            return hasValidLength && startsWithNine;
          },
          message: m.mobileInvalid,
        )
        .transformTyped(_digitsOnly);
  }

  static String _digitsOnly(String value) {
    return value.replaceAll(_nonDigitsPattern, '');
  }

  static Result<AgentProfile> _parseProfile(
    dynamic payload,
    AgentProfileValidationMessages messages,
  ) {
    final schema = _profileSchemaFor(messages);
    final result = schema.parseSafe(_normalizePayload(payload));
    if (result.isError()) {
      return Failure(result.exceptionOrNull()!);
    }

    return Success(AgentProfile.fromMap(result.getOrThrow()));
  }

  static dynamic _normalizePayload(dynamic payload) {
    if (payload is! Map<String, dynamic>) {
      return payload;
    }

    final address = payload['address'];
    final normalizedAddress = address is Map<String, dynamic>
        ? <String, dynamic>{
            'street': (address['street'] as String? ?? '').trim(),
            'number': (address['number'] as String? ?? '').trim(),
            'district': (address['district'] as String? ?? '').trim(),
            'postal_code': _digitsOnly(address['postal_code'] as String? ?? ''),
            'city': (address['city'] as String? ?? '').trim(),
            'state': (address['state'] as String? ?? '').trim().toUpperCase(),
          }
        : address;

    return <String, dynamic>{
      ...payload,
      'name': (payload['name'] as String? ?? '').trim(),
      'trade_name': (payload['trade_name'] as String? ?? '').trim(),
      'document': _digitsOnly(payload['document'] as String? ?? ''),
      'document_type': (payload['document_type'] as String? ?? '').trim().toLowerCase(),
      if (payload.containsKey('phone')) 'phone': _digitsOnly(payload['phone'] as String? ?? ''),
      'mobile': _digitsOnly(payload['mobile'] as String? ?? ''),
      'email': (payload['email'] as String? ?? '').trim().toLowerCase(),
      'address': normalizedAddress,
      if (payload.containsKey('notes')) 'notes': (payload['notes'] as String? ?? '').trim(),
    };
  }

  static String _resolveDocumentType(String document) {
    return _digitsOnly(document).length == 14 ? 'cnpj' : 'cpf';
  }

  static bool _isValidCpfOrCnpj(String value) {
    final digits = _digitsOnly(value);
    if (digits.length == 11) {
      return _isValidCpf(digits);
    }
    if (digits.length == 14) {
      return _isValidCnpj(digits);
    }
    return false;
  }

  static bool _isAllDigitsEqual(String digits) {
    if (digits.isEmpty) {
      return true;
    }

    return digits.split('').every((String digit) => digit == digits[0]);
  }

  static bool _isValidCpf(String cpf) {
    if (cpf.length != 11 || _isAllDigitsEqual(cpf)) {
      return false;
    }

    final numbers = cpf.split('').map(int.parse).toList(growable: false);
    final firstCheck = _cpfCheckDigit(numbers, 9);
    final secondCheck = _cpfCheckDigit(numbers, 10);
    return numbers[9] == firstCheck && numbers[10] == secondCheck;
  }

  static int _cpfCheckDigit(List<int> digits, int length) {
    var sum = 0;
    for (var i = 0; i < length; i++) {
      sum += digits[i] * ((length + 1) - i);
    }

    final mod = (sum * 10) % 11;
    return mod == 10 ? 0 : mod;
  }

  static bool _isValidCnpj(String cnpj) {
    if (cnpj.length != 14 || _isAllDigitsEqual(cnpj)) {
      return false;
    }

    final numbers = cnpj.split('').map(int.parse).toList(growable: false);
    final firstCheck = _cnpjCheckDigit(
      numbers,
      const <int>[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
    );
    final secondCheck = _cnpjCheckDigit(
      numbers,
      const <int>[6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
    );
    return numbers[12] == firstCheck && numbers[13] == secondCheck;
  }

  static int _cnpjCheckDigit(List<int> digits, List<int> weights) {
    var sum = 0;
    for (var i = 0; i < weights.length; i++) {
      sum += digits[i] * weights[i];
    }

    final mod = sum % 11;
    return mod < 2 ? 0 : 11 - mod;
  }
}
