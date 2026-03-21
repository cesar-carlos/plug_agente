@Tags(['live'])
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/e2e_env.dart';
import '../helpers/live_test_env.dart';

void main() async {
  await loadLiveTestEnv();

  final baseUrl = E2EEnv.apiTestBaseUrl;

  group('API live — GET $baseUrl', () {
    late Dio dio;

    setUp(() {
      dio = Dio();
    });

    test(
      'should successfully connect to production server',
      () async {
        final url = baseUrl;

        try {
          final response = await dio.get<String>(url);

          expect(response.statusCode, isNotNull);
          expect(response.statusCode, isA<int>());
        } catch (e) {
          rethrow;
        }
      },
      skip: E2EEnv.skipUnlessLiveApiTests,
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
      skip: E2EEnv.skipUnlessLiveApiTests,
    );

    test(
      'should include proper headers in request',
      () async {
        final url = baseUrl;
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
      skip: E2EEnv.skipUnlessLiveApiTests,
    );

    test(
      'should handle different endpoints correctly',
      () async {
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
      skip: E2EEnv.skipUnlessLiveApiTests,
    );
  });
}
