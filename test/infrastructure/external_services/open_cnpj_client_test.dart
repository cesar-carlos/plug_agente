import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/open_cnpj_client.dart';

void main() {
  group('OpenCnpjClient', () {
    test('should return company data when API responds 200', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'cnpj': '11222333000181',
                  'razao_social': 'ACME LTDA',
                  'nome_fantasia': 'ACME',
                  'logradouro': 'Rua A',
                  'numero': '1',
                  'bairro': 'Centro',
                  'cep': '01310100',
                  'municipio': 'SAO PAULO',
                  'uf': 'SP',
                  'telefones': <dynamic>[
                    <String, dynamic>{
                      'ddd': '11',
                      'numero': '34567890',
                      'is_fax': false,
                    },
                    <String, dynamic>{
                      'ddd': '11',
                      'numero': '987654321',
                      'is_fax': false,
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

      final client = OpenCnpjClient(dio);
      final result = await client.lookupCnpj(
        '11222333000181',
      );

      expect(result.isSuccess(), isTrue);
      final data = result.getOrThrow();
      expect(data.legalName, 'ACME LTDA');
      expect(data.tradeName, 'ACME');
      expect(data.phone, '1134567890');
      expect(data.mobile, '11987654321');
    });

    test('should return ValidationFailure on 404', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<void>(
                  requestOptions: options,
                  statusCode: 404,
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final client = OpenCnpjClient(dio);
      final result = await client.lookupCnpj('11222333000181');

      expect(result.isError(), isTrue);
      final err = result.exceptionOrNull();
      expect(err, isA<domain.ValidationFailure>());
      expect(
        (err! as domain.Failure).message,
        AppStrings.msgOpenCnpjNotFound,
      );
    });

    test('should return ServerFailure on 429', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<void>(
                  requestOptions: options,
                  statusCode: 429,
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final client = OpenCnpjClient(dio);
      final result = await client.lookupCnpj('11222333000181');

      expect(result.isError(), isTrue);
      final err = result.exceptionOrNull();
      expect(err, isA<domain.ServerFailure>());
      expect(
        (err! as domain.Failure).message,
        AppStrings.msgOpenCnpjRateLimit,
      );
    });

    test('should return ServerFailure when razao_social is missing', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'cnpj': '11222333000181',
                },
              ),
            );
          },
        ),
      );

      final client = OpenCnpjClient(dio);
      final result = await client.lookupCnpj('11222333000181');

      expect(result.isError(), isTrue);
      final err = result.exceptionOrNull();
      expect(err, isA<domain.ServerFailure>());
      expect(
        (err! as domain.Failure).message,
        AppStrings.msgOpenCnpjInvalidPayload,
      );
    });
  });
}
