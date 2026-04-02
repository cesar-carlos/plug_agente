import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/via_cep_client.dart';

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
      final result = await client.lookupCep('01001000');

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
      final result = await client.lookupCep('00000000');

      expect(result.isError(), isTrue);
      final err = result.exceptionOrNull();
      expect(err, isA<domain.ValidationFailure>());
      expect(
        (err! as domain.Failure).message,
        AppStrings.msgViaCepNotFound,
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
        final result = await client.lookupCep('01001000');

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ServerFailure>());
        expect(
          (err! as domain.Failure).message,
          AppStrings.msgViaCepInvalidPayload,
        );
      },
    );
  });
}
