import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plug_agente/application/services/update_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

class MockDio extends Mock implements Dio {}

void main() {
  group('UpdateService', () {
    late MockDio mockDio;
    late UpdateService service;

    setUp(() {
      mockDio = MockDio();
      service = UpdateService('https://updates.example.com', mockDio);
      PackageInfo.setMockInitialValues(
        appName: 'Plug Agente',
        packageName: 'plug_agente',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
    });

    test('should return success when update is available', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          'https://updates.example.com/check',
          queryParameters: {'currentVersion': '1.0.0'},
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/check'),
          statusCode: 200,
          data: {'updateAvailable': true},
        ),
      );

      final result = await service.checkForUpdates();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), isTrue);
    });

    test('should return server failure when status code is not 200', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          'https://updates.example.com/check',
          queryParameters: {'currentVersion': '1.0.0'},
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/check'),
          statusCode: 503,
          data: {'updateAvailable': false},
        ),
      );

      final result = await service.checkForUpdates();
      final failure = result.exceptionOrNull()! as domain.ServerFailure;

      expect(result.isError(), isTrue);
      expect(failure.message, 'Unable to verify updates right now');
      expect(failure.context, containsPair('statusCode', 503));
    });

    test('should return server failure when response data is null', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          'https://updates.example.com/check',
          queryParameters: {'currentVersion': '1.0.0'},
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/check'),
          statusCode: 200,
        ),
      );

      final result = await service.checkForUpdates();
      final failure = result.exceptionOrNull()! as domain.ServerFailure;

      expect(result.isError(), isTrue);
      expect(failure.message, 'Update server returned an empty response');
      expect(failure.context, containsPair('operation', 'checkForUpdates'));
    });

    test('should return network failure on DioException', () async {
      final exception = DioException(
        requestOptions: RequestOptions(path: '/check'),
        type: DioExceptionType.connectionError,
        error: Exception('offline'),
      );

      when(
        () => mockDio.get<Map<String, dynamic>>(
          'https://updates.example.com/check',
          queryParameters: {'currentVersion': '1.0.0'},
        ),
      ).thenThrow(exception);

      final result = await service.checkForUpdates();
      final failure = result.exceptionOrNull()! as domain.NetworkFailure;

      expect(result.isError(), isTrue);
      expect(
        failure.message,
        'Unable to check for updates. Check your connection and try again.',
      );
      expect(failure.cause, exception);
      expect(failure.context, containsPair('operation', 'checkForUpdates'));
    });
  });
}
