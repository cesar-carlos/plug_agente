import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/infrastructure/external_services/auth_client.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockDio dio;
  late AuthClient client;

  setUp(() {
    dio = _MockDio();
    client = AuthClient(dio);
  });

  group('AuthClient', () {
    test('should map refresh 401 with structured error payload to validation failure', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/auth/refresh'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/api/auth/refresh'),
            statusCode: 401,
            data: <String, dynamic>{
              'error': <String, dynamic>{
                'message': 'Refresh token expired or revoked',
              },
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await client.refreshToken('https://hub.example', 'refresh-token');

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ValidationFailure>());
      expect((failure! as domain.Failure).message, 'Refresh token expired or revoked');
    });

    test('should map refresh 401 with non-object payload to fallback validation failure', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/auth/refresh'),
          response: Response<String>(
            requestOptions: RequestOptions(path: '/api/auth/refresh'),
            statusCode: 401,
            data: 'unauthorized',
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await client.refreshToken('https://hub.example', 'refresh-token');

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ValidationFailure>());
      expect((failure! as domain.Failure).message, 'Refresh token expired or revoked');
    });

    test('should map login 401 with structured error payload to validation failure', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/auth/agent/login'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/api/auth/agent/login'),
            statusCode: 401,
            data: <String, dynamic>{
              'error': <String, dynamic>{
                'reason': 'Invalid credentials',
              },
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await client.login('https://hub.example', AuthCredentials.test());

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ValidationFailure>());
      expect((failure! as domain.Failure).message, 'Invalid credentials');
    });

    test('should map invalid 200 auth payload with structured error to validation failure', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/auth/agent/login'),
          statusCode: 200,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'message': 'Auth response did not include tokens',
            },
          },
        ),
      );

      final result = await client.login('https://hub.example', AuthCredentials.test());

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ValidationFailure>());
      expect((failure! as domain.Failure).message, 'Auth response did not include tokens');
    });
  });
}
