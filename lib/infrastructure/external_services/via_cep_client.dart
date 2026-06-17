import 'package:dio/dio.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/agent_profile_lookup_error_messages.dart';
import 'package:plug_agente/domain/services/agent_profile_lookup_gateways.dart';
import 'package:result_dart/result_dart.dart';

class ViaCepClient implements IViaCepLookup {
  ViaCepClient(this._dio);

  final Dio _dio;

  @override
  Future<Result<ViaCepAddress>> lookupCep(
    String cepDigits, {
    required ViaCepLookupErrorMessages errorMessages,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://viacep.com.br/ws/$cepDigits/json/',
      );
      final payload = response.data;
      if (payload == null) {
        return Failure(
          domain.ValidationFailure(errorMessages.emptyResponse),
        );
      }

      if (payload['erro'] == true) {
        return Failure(
          domain.ValidationFailure(errorMessages.notFound),
        );
      }

      final cep = payload['cep'];
      final logradouro = payload['logradouro'];
      final bairro = payload['bairro'];
      final localidade = payload['localidade'];
      final uf = payload['uf'];
      if (cep is! String || logradouro is! String || bairro is! String || localidade is! String || uf is! String) {
        return Failure(
          domain.ServerFailure(errorMessages.invalidPayload),
        );
      }

      return Success(
        ViaCepAddress(
          cep: cep,
          logradouro: logradouro,
          bairro: bairro,
          localidade: localidade,
          uf: uf,
        ),
      );
    } on DioException catch (error) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: errorMessages.networkError,
          cause: error,
          context: {'service': 'viacep'},
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: errorMessages.unexpectedError,
          cause: error,
          context: {'service': 'viacep'},
        ),
      );
    }
  }
}
