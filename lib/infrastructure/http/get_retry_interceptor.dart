import 'dart:math';

import 'package:dio/dio.dart';

/// Computes backoff delay for GET retries with optional jitter.
///
/// Exposed for unit tests.
int computeGetRetryBackoffMs({
  required int retryCount,
  required int initialDelayMs,
  required int maxDelayMs,
  double jitterFraction = 0.15,
  Random? random,
}) {
  final base = initialDelayMs * (1 << retryCount);
  final capped = base > maxDelayMs ? maxDelayMs : base;
  final rng = random ?? Random();
  final jitterFactor = (rng.nextDouble() * 2 - 1) * jitterFraction;
  final jittered = (capped * (1 + jitterFactor)).round();
  return jittered.clamp(50, maxDelayMs);
}

/// Retries GET requests on transient failures (idempotent, safe to retry).
///
/// Does not retry POST or other mutating methods.
class GetRetryInterceptor extends Interceptor {
  GetRetryInterceptor({
    required this.dio,
    this.maxRetries = 2,
    this.initialDelayMs = 300,
    this.maxDelayMs = 2000,
    this.jitterFraction = 0.15,
    Random? random,
  }) : _random = random;

  final Dio dio;
  final int maxRetries;
  final int initialDelayMs;
  final int maxDelayMs;
  final double jitterFraction;
  final Random? _random;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.requestOptions.method != 'GET') {
      return handler.next(err);
    }

    final retryCount = err.requestOptions.extra['_retryCount'] as int? ?? 0;
    if (retryCount >= maxRetries) {
      return handler.next(err);
    }

    if (!_isRetryable(err)) {
      return handler.next(err);
    }

    final delayMs = _backoffDelay(retryCount);
    await Future<void>.delayed(Duration(milliseconds: delayMs));

    final options = err.requestOptions;
    options.extra['_retryCount'] = retryCount + 1;

    try {
      final response = await dio.fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  bool _isRetryable(DioException err) {
    return switch (err.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      DioExceptionType.badResponse => _isRetryableStatus(
        err.response?.statusCode,
      ),
      _ => false,
    };
  }

  bool _isRetryableStatus(int? status) {
    if (status == null) return false;
    return status >= 500 && status < 600;
  }

  int _backoffDelay(int retryCount) {
    return computeGetRetryBackoffMs(
      retryCount: retryCount,
      initialDelayMs: initialDelayMs,
      maxDelayMs: maxDelayMs,
      jitterFraction: jitterFraction,
      random: _random,
    );
  }
}
