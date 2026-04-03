import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/http/get_retry_interceptor.dart';

void main() {
  group('GetRetryInterceptor', () {
    test('should retry GET on connection timeout and succeed on second attempt', () async {
      final dio = Dio();
      var attempts = 0;
      dio.interceptors.add(
        GetRetryInterceptor(
          dio: dio,
          initialDelayMs: 1,
          maxDelayMs: 100,
          random: Random(0),
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            attempts++;
            if (attempts == 1) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                ),
                true,
              );
            } else {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  data: 'ok',
                  statusCode: 200,
                ),
              );
            }
          },
        ),
      );

      final response = await dio.get<dynamic>('http://example.test/data');
      expect(response.data, 'ok');
      expect(attempts, 2);
    });

    test('should not retry non-GET requests', () async {
      final dio = Dio();
      var attempts = 0;
      dio.interceptors.add(
        GetRetryInterceptor(
          dio: dio,
          initialDelayMs: 1,
          maxDelayMs: 100,
          random: Random(0),
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            attempts++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
              true,
            );
          },
        ),
      );

      await expectLater(
        dio.post<dynamic>('http://example.test/p'),
        throwsA(isA<DioException>()),
      );
      expect(attempts, 1);
    });

    test('should not retry non-retryable badResponse status', () async {
      final dio = Dio();
      dio.interceptors.add(
        GetRetryInterceptor(
          dio: dio,
          initialDelayMs: 1,
          maxDelayMs: 100,
          random: Random(0),
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 404,
                ),
              ),
              true,
            );
          },
        ),
      );

      await expectLater(
        dio.get<dynamic>('http://example.test/missing'),
        throwsA(isA<DioException>()),
      );
    });

    test('should retry on 503 and eventually resolve', () async {
      final dio = Dio();
      var attempts = 0;
      dio.interceptors.add(
        GetRetryInterceptor(
          dio: dio,
          initialDelayMs: 1,
          maxDelayMs: 100,
          random: Random(0),
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            attempts++;
            if (attempts == 1) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 503,
                  ),
                ),
                true,
              );
            } else {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  data: 'recovered',
                  statusCode: 200,
                ),
              );
            }
          },
        ),
      );

      final response = await dio.get<dynamic>('http://example.test/r');
      expect(response.data, 'recovered');
      expect(attempts, 2);
    });
  });

  group('computeGetRetryBackoffMs', () {
    test('should return delay within jitter bounds with seeded random', () {
      const initialDelayMs = 300;
      const maxDelayMs = 2000;
      final random = Random(42);

      for (var retryCount = 0; retryCount <= 3; retryCount++) {
        final delay = computeGetRetryBackoffMs(
          retryCount: retryCount,
          initialDelayMs: initialDelayMs,
          maxDelayMs: maxDelayMs,
          random: random,
        );

        final base = initialDelayMs * (1 << retryCount);
        final capped = base > maxDelayMs ? maxDelayMs : base;
        final minMs = (capped * 0.85).round();
        final maxMs = (capped * 1.15).round();

        expect(
          delay,
          greaterThanOrEqualTo(minMs),
          reason: 'retryCount $retryCount: $delay should be >= $minMs',
        );
        expect(
          delay,
          lessThanOrEqualTo(maxMs),
          reason: 'retryCount $retryCount: $delay should be <= $maxMs',
        );
      }
    });

    test('should cap at maxDelayMs', () {
      const initialDelayMs = 500;
      const maxDelayMs = 1000;
      final random = Random(0);

      final delay = computeGetRetryBackoffMs(
        retryCount: 5,
        initialDelayMs: initialDelayMs,
        maxDelayMs: maxDelayMs,
        random: random,
      );

      expect(delay, lessThanOrEqualTo(maxDelayMs));
      expect(delay, greaterThanOrEqualTo(850));
    });

    test('should enforce minimum 50ms', () {
      const initialDelayMs = 10;
      const maxDelayMs = 500;
      final random = Random(0);

      final delay = computeGetRetryBackoffMs(
        retryCount: 0,
        initialDelayMs: initialDelayMs,
        maxDelayMs: maxDelayMs,
        jitterFraction: 0.5,
        random: random,
      );

      expect(delay, greaterThanOrEqualTo(50));
    });
  });
}
