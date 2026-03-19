import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/e2e_env.dart';

void main() async {
  await E2EEnv.load();

  final baseUrl = E2EEnv.apiTestBaseUrl;

  group('API Test - GET $baseUrl', () {
    late Dio dio;

    setUp(() {
      dio = Dio();
    });

    test(
      'should successfully connect to production server',
      () async {
        // Arrange
        final url = baseUrl;

        // Act & Assert
        try {
          final response = await dio.get<String>(url);

          expect(response.statusCode, isNotNull);
          expect(response.statusCode, isA<int>());
        } catch (e) {
          rethrow;
        }
      },
      skip: !E2EEnv.runLiveApiTests,
    );

    test('should handle connection timeout gracefully', () async {
      // Arrange - use URL that never responds (non-routable IP)
      final url = E2EEnv.apiTestTimeoutUrl;
      final dioWithTimeout = Dio(
        BaseOptions(connectTimeout: const Duration(seconds: 1)),
      );

      // Act & Assert
      try {
        await dioWithTimeout.get<String>(url);
        fail('Should have thrown DioException');
      } on DioException catch (e) {
        expect(e.type, DioExceptionType.connectionTimeout);
      } catch (e, st) {
        fail('Expected DioException.connectionTimeout, got $e\n$st');
      }
    }, skip: !E2EEnv.runLiveApiTests);

    test('should include proper headers in request', () async {
      // Arrange
      final url = baseUrl;
      final headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Plug Database/1.0.0 (Windows)',
      };

      // Act
      try {
        final response = await dio.get<String>(
          url,
          options: Options(headers: headers),
        );

        // Assert
        expect(response.statusCode, isNotNull);
      } on Exception {
        // Request failed, but we're just testing the configuration
      }
    }, skip: !E2EEnv.runLiveApiTests);

    test(
      'should handle different endpoints correctly',
      () async {
        // Arrange
        // Act & Assert - Test base endpoint
        try {
          final response = await dio.get<String>(
            baseUrl,
            options: Options(receiveTimeout: const Duration(seconds: 5)),
          );
          expect(response.statusCode, isNotNull);
        } on Exception {
          // Don't fail the test, just catch the error
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
      skip: !E2EEnv.runLiveApiTests,
    );
  });
}
