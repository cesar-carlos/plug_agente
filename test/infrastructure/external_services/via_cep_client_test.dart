import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/agent_profile_lookup_error_messages.dart';
import 'package:plug_agente/infrastructure/external_services/via_cep_client.dart';

const _testErrorMessages = ViaCepLookupErrorMessages(
  emptyResponse: 'empty response',
  notFound: 'not found',
  invalidPayload: 'invalid payload',
  networkError: 'network error',
  unexpectedError: 'unexpected error',
);

void main() {
  group('ViaCepClient', () {
    test('should return address when API responds 200', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'cep': '01001-000',
                  'logradouro': 'Praça da Sé',
                  'bairro': 'Sé',
                  'localidade': 'São Paulo',
                  'uf': 'SP',
                },
              ),
            );
          },
        ),
      );

      final client = ViaCepClient(dio);
      final result = await client.lookupCep(
        '01001000',
        errorMessages: _testErrorMessages,
      );

      expect(result.isSuccess(), isTrue);
      final address = result.getOrThrow();
      expect(address.logradouro, 'Praça da Sé');
      expect(address.localidade, 'São Paulo');
      expect(address.uf, 'SP');
    });

    test('should return ValidationFailure when erro is true', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{'erro': true},
              ),
            );
          },
        ),
      );

      final client = ViaCepClient(dio);
      final result = await client.lookupCep(
        '00000000',
        errorMessages: _testErrorMessages,
      );

      expect(result.isError(), isTrue);
      final err = result.exceptionOrNull();
      expect(err, isA<domain.ValidationFailure>());
      expect(
        (err! as domain.Failure).message,
        _testErrorMessages.notFound,
      );
    });

    test(
      'should return ServerFailure when required fields are missing',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'cep': '01001-000',
                  },
                ),
              );
            },
          ),
        );

        final client = ViaCepClient(dio);
        final result = await client.lookupCep(
          '01001000',
          errorMessages: _testErrorMessages,
        );

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ServerFailure>());
        expect(
          (err! as domain.Failure).message,
          _testErrorMessages.invalidPayload,
        );
      },
    );
  });
}
