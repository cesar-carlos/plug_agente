import 'package:dio/dio.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/agent_profile_lookup_error_messages.dart';
import 'package:plug_agente/domain/services/agent_profile_lookup_gateways.dart';
import 'package:result_dart/result_dart.dart';

class OpenCnpjClient implements IOpenCnpjLookup {
  OpenCnpjClient(this._dio);

  static const String apiBaseUrl = 'https://api.opencnpj.org';

  final Dio _dio;

  @override
  Future<Result<OpenCnpjCompanyData>> lookupCnpj(
    String cnpjDigits, {
    required OpenCnpjLookupErrorMessages errorMessages,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$apiBaseUrl/$cnpjDigits',
      );
      final payload = response.data;
      if (payload == null) {
        return Failure(
          domain.ValidationFailure(errorMessages.emptyResponse),
        );
      }

      final document = _readString(payload, 'cnpj');
      final legalName = _readString(payload, 'razao_social');
      if (document == null || legalName == null) {
        return Failure(
          domain.ServerFailure(errorMessages.invalidPayload),
        );
      }

      final phones = _extractPhones(payload['telefones']);
      return Success(
        OpenCnpjCompanyData(
          cnpj: document,
          legalName: legalName,
          tradeName: _readOptionalString(payload, 'nome_fantasia'),
          email: _readOptionalString(payload, 'email'),
          street: _readOptionalString(payload, 'logradouro'),
          number: _readOptionalString(payload, 'numero'),
          district: _readOptionalString(payload, 'bairro'),
          postalCode: _readOptionalString(payload, 'cep'),
          city: _readOptionalString(payload, 'municipio'),
          state: _readOptionalString(payload, 'uf'),
          phone: phones.phone,
          mobile: phones.mobile,
        ),
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 404) {
        return Failure(
          domain.ValidationFailure(errorMessages.notFound),
        );
      }
      if (statusCode == 429) {
        return Failure(
          domain.ServerFailure(errorMessages.rateLimit),
        );
      }

      return Failure(
        domain.NetworkFailure.withContext(
          message: errorMessages.networkError,
          cause: error,
          context: {'service': 'opencnpj'},
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: errorMessages.unexpectedError,
          cause: error,
          context: {'service': 'opencnpj'},
        ),
      );
    }
  }

  String? _readString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is! String) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _readOptionalString(Map<String, dynamic> payload, String key) {
    return _readString(payload, key);
  }

  _OpenCnpjPhones _extractPhones(dynamic rawPhones) {
    if (rawPhones is! List<dynamic>) {
      return const _OpenCnpjPhones();
    }

    String? phone;
    String? mobile;

    for (final entry in rawPhones) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }

      final ddd = _readString(entry, 'ddd');
      final number = _readString(entry, 'numero');
      final isFax = entry['is_fax'] == true;
      if (ddd == null || number == null || isFax) {
        continue;
      }

      final digits = '$ddd$number';
      if (number.length == 9 && number.startsWith('9')) {
        mobile ??= digits;
      } else {
        phone ??= digits;
      }
    }

    return _OpenCnpjPhones(phone: phone, mobile: mobile);
  }
}

class _OpenCnpjPhones {
  const _OpenCnpjPhones({
    this.phone,
    this.mobile,
  });

  final String? phone;
  final String? mobile;
}
