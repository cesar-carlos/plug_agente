import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/infrastructure/external_services/hub_availability_probe.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockDio dio;
  late HubAvailabilityProbe probe;

  setUp(() {
    dio = _MockDio();
    probe = HubAvailabilityProbe(dio: dio);
  });

  group('HubAvailabilityProbe', () {
    test('returns true when probe receives an HTTP response', () async {
      when(() => dio.get<void>(any())).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: '/health'),
          statusCode: 200,
        ),
      );

      final reachable = await probe.isServerReachable('https://hub.test');

      expect(reachable, isTrue);
      verify(
        () => dio.get<void>('https://hub.test${AppConstants.defaultHubAvailabilityProbePath}'),
      ).called(1);
    });

    test('strips /agents namespace before appending probe path', () async {
      when(() => dio.get<void>(any())).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: '/health'),
          statusCode: 200,
        ),
      );

      final reachable = await probe.isServerReachable('https://hub.test/agents');

      expect(reachable, isTrue);
      verify(
        () => dio.get<void>('https://hub.test${AppConstants.defaultHubAvailabilityProbePath}'),
      ).called(1);
      verifyNever(() => dio.get<void>('https://hub.test/agents${AppConstants.defaultHubAvailabilityProbePath}'));
    });

    test('returns true when DioException includes an HTTP response', () async {
      when(() => dio.get<void>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/health'),
          response: Response<void>(
            requestOptions: RequestOptions(path: '/health'),
            statusCode: 503,
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final reachable = await probe.isServerReachable('https://hub.test');

      expect(reachable, isTrue);
    });

    test('returns false when DioException has no HTTP response', () async {
      when(() => dio.get<void>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/health'),
          type: DioExceptionType.connectionTimeout,
          message: 'connection timed out',
        ),
      );

      final reachable = await probe.isServerReachable('https://hub.test');

      expect(reachable, isFalse);
    });

    test('returns false when probe throws a generic exception', () async {
      when(() => dio.get<void>(any())).thenThrow(
        const FormatException('invalid probe response'),
      );

      final reachable = await probe.isServerReachable('https://hub.test');

      expect(reachable, isFalse);
    });
  });
}
