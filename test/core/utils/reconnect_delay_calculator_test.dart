import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/reconnect_delay_calculator.dart';

void main() {
  group('computeReconnectDelay', () {
    test('should return delay within jitter bounds with seeded random', () {
      const initial = Duration(seconds: 1);
      const max = Duration(seconds: 60);
      final random = Random(42);

      for (var attempt = 1; attempt <= 6; attempt++) {
        final delay = computeReconnectDelay(
          attempt: attempt,
          initialDelay: initial,
          maxDelay: max,
          random: random,
        );

        final baseSeconds = (1 << (attempt - 1).clamp(0, 5)).toDouble();
        final cappedSeconds = baseSeconds > 60 ? 60.0 : baseSeconds;
        final minMs = (cappedSeconds * 1000 * 0.85).round();
        final maxMs = (cappedSeconds * 1000 * 1.15).round();

        expect(
          delay.inMilliseconds,
          greaterThanOrEqualTo(minMs),
          reason: 'attempt $attempt: $delay should be >= ${minMs}ms',
        );
        expect(
          delay.inMilliseconds,
          lessThanOrEqualTo(maxMs),
          reason: 'attempt $attempt: $delay should be <= ${maxMs}ms',
        );
      }
    });

    test('should cap at maxDelay', () {
      const initial = Duration(seconds: 10);
      const max = Duration(seconds: 5);
      final random = Random(0);

      final delay = computeReconnectDelay(
        attempt: 10,
        initialDelay: initial,
        maxDelay: max,
        random: random,
      );

      expect(delay.inMilliseconds, lessThanOrEqualTo(5750));
      expect(delay.inMilliseconds, greaterThanOrEqualTo(4250));
    });

    test('should enforce minimum 100ms', () {
      const initial = Duration(milliseconds: 50);
      const max = Duration(seconds: 1);
      final random = Random(0);

      final delay = computeReconnectDelay(
        attempt: 1,
        initialDelay: initial,
        maxDelay: max,
        jitterFraction: 0.5,
        random: random,
      );

      expect(delay.inMilliseconds, greaterThanOrEqualTo(100));
    });
  });
}
