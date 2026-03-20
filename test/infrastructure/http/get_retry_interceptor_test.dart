import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/http/get_retry_interceptor.dart';

void main() {
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
