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

  static final Schema<Map<String, dynamic>> _addressSchema = z.interface(
    <String, Schema<dynamic>>{
      'street': _requiredText(
        label: 'Endereco',
        maxLength: 100,
      ),
      'number': _requiredText(
        label: 'Numero do endereco',
        maxLength: 15,
      ),
      'district': _requiredText(
        label: 'Bairro',
        maxLength: 60,
      ),
      'postal_code': _postalCodeSchema(),
      'city': _requiredText(
        label: 'Municipio',
        maxLength: 60,
      ),
      'state': z.string().trim().toUpperCase().refine(
        _statePattern.hasMatch,
        message: 'UF deve conter exatamente 2 letras.',
      ),
    },
  ).strict();

  static final Schema<Map<String, dynamic>> _schema = z
      .interface(<String, Schema<dynamic>>{
        'name': _requiredText(
          label: 'Nome',
          maxLength: 100,
        ),
        'trade_name': _requiredText(
          label: 'Nome fantasia',
          maxLength: 100,
        ),
        'document': _documentSchema(),
        'document_type': z.$enum(
          const <String>['cpf', 'cnpj'],
          message: 'Tipo de documento deve ser cpf ou cnpj.',
        ),
        'phone?': _phoneSchema(),
        'mobile': _mobileSchema(),
        'email': z.string().trim().toLowerCase().email(
          pattern: z.regexes.email,
          message: 'E-mail invalido.',
        ),
        'address': _addressSchema,
        'notes?': z.string().trim().max(
          2000,
          message: 'Observacao deve ter no maximo 2000 caracteres.',
        ),
      })
      .strict()
      .refine(
        (Map<String, dynamic> value) => value['document_type'] == _resolveDocumentType(value['document'] as String),
        message: 'Tipo de documento nao corresponde ao CPF/CNPJ informado.',
      );

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
  }) {
    final normalizedDocument = _digitsOnly(document);

    return _parseProfile(<String, dynamic>{
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
    });
  }

  static Result<AgentProfile> fromConfig(Config config) {
    final normalizedDocument = _digitsOnly(config.cnaeCnpjCpf);

    return _parseProfile(<String, dynamic>{
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
    });
  }

  static Result<AgentProfile> fromRpcPayload(dynamic payload) {
    return _parseProfile(payload);
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

  static Schema<String> _requiredText({
    required String label,
    required int maxLength,
  }) {
    return z
        .string()
        .trim()
        .min(1, message: '$label e obrigatorio.')
        .max(
          maxLength,
          message: '$label deve ter no maximo $maxLength caracteres.',
        );
  }

  static Schema<String> _documentSchema() {
    return z
        .string()
        .trim()
        .refine(
          _isValidCpfOrCnpj,
          message: 'CNPJ/CPF invalido.',
        )
        .transformTyped(_digitsOnly);
  }

  static Schema<String> _postalCodeSchema() {
    return z
        .string()
        .trim()
        .refine(
          (String value) {
            final digits = _digitsOnly(value);
            return digits.length == 8 && _digitsOnlyPattern.hasMatch(digits);
          },
          message: 'CEP invalido. Informe 8 digitos.',
        )
        .transformTyped(_digitsOnly);
  }

  static Schema<String> _phoneSchema() {
    return z
        .string()
        .trim()
        .refine(
          (String value) {
            final digits = _digitsOnly(value);
            return digits.length == 10 && _digitsOnlyPattern.hasMatch(digits);
          },
          message: 'Telefone invalido.',
        )
        .transformTyped(_digitsOnly);
  }

  static Schema<String> _mobileSchema() {
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
          message: 'Celular invalido.',
        )
        .transformTyped(_digitsOnly);
  }

  static String _digitsOnly(String value) {
    return value.replaceAll(_nonDigitsPattern, '');
  }

  static Result<AgentProfile> _parseProfile(dynamic payload) {
    final result = _schema.parseSafe(_normalizePayload(payload));
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
