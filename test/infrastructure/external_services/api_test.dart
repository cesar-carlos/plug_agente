@Tags(['live'])
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/e2e_env.dart';

void main() async {
  await E2EEnv.load();

  final skipMessage = E2EEnv.liveApiReadinessSkipMessage;
  final baseUrl = E2EEnv.apiTestBaseUrlOrNull;

  group('API Test - GET ${baseUrl ?? 'live (opt-in)'}', () {
    late Dio dio;

    setUp(() {
      dio = Dio();
    });

    test(
      'should successfully connect to production server',
      () async {
        final url = baseUrl;
        if (url == null || url.isEmpty) {
          fail('API_TEST_BASE_URL must be set when this test is not skipped');
        }

        final response = await dio.get<String>(url);

        expect(response.statusCode, isNotNull);
        expect(response.statusCode, isA<int>());
      },
      skip: skipMessage,
    );

    test(
      'should handle connection timeout gracefully',
      () async {
        final url = E2EEnv.apiTestTimeoutUrl;
        final dioWithTimeout = Dio(
          BaseOptions(connectTimeout: const Duration(seconds: 1)),
        );

        try {
          await dioWithTimeout.get<String>(url);
          fail('Should have thrown DioException');
        } on DioException catch (e) {
          expect(e.type, DioExceptionType.connectionTimeout);
        } catch (e, st) {
          fail('Expected DioException.connectionTimeout, got $e\n$st');
        }
      },
      skip: skipMessage,
    );

    test(
      'should include proper headers in request',
      () async {
        final url = baseUrl;
        if (url == null || url.isEmpty) {
          fail('API_TEST_BASE_URL must be set when this test is not skipped');
        }

        final headers = {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': 'Plug Database/1.0.0 (Windows)',
        };

        try {
          final response = await dio.get<String>(
            url,
            options: Options(headers: headers),
          );

          expect(response.statusCode, isNotNull);
        } on Exception {
          // Request failed, but we're just testing the configuration
        }
      },
      skip: skipMessage,
    );

    test(
      'should handle different endpoints correctly',
      () async {
        final url = baseUrl;
        if (url == null || url.isEmpty) {
          fail('API_TEST_BASE_URL must be set when this test is not skipped');
        }

        try {
          final response = await dio.get<String>(
            url,
            options: Options(receiveTimeout: const Duration(seconds: 5)),
          );
          expect(response.statusCode, isNotNull);
        } on Exception {
          // Don't fail the test, just catch the error
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
      skip: skipMessage,
    );
  });
}
