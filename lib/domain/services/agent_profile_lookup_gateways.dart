import 'package:result_dart/result_dart.dart';

class OpenCnpjCompanyData {
  const OpenCnpjCompanyData({
    required this.cnpj,
    required this.legalName,
    this.tradeName,
    this.email,
    this.street,
    this.number,
    this.district,
    this.postalCode,
    this.city,
    this.state,
    this.phone,
    this.mobile,
  });

  final String cnpj;
  final String legalName;
  final String? tradeName;
  final String? email;
  final String? street;
  final String? number;
  final String? district;
  final String? postalCode;
  final String? city;
  final String? state;
  final String? phone;
  final String? mobile;
}

class ViaCepAddress {
  const ViaCepAddress({
    required this.cep,
    required this.logradouro,
    required this.bairro,
    required this.localidade,
    required this.uf,
  });

  final String cep;
  final String logradouro;
  final String bairro;
  final String localidade;
  final String uf;
}

/// Application boundary for CNPJ lookup providers.
///
/// Receives the already sanitized 14 digit CNPJ and returns a tipped result
/// that the presentation layer can consume without depending on transport
/// implementation details.
abstract interface class IOpenCnpjLookup {
  Future<Result<OpenCnpjCompanyData>> lookupCnpj(String cnpjDigits);
}

/// Application boundary for postal code lookup providers.
abstract interface class IViaCepLookup {
  Future<Result<ViaCepAddress>> lookupCep(String cepDigits);
}
