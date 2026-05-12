import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/logger/log_rate_limiter.dart';

void main() {
  group('LogRateLimiter', () {
    test('should allow initial burst and then stride logs', () {
      final limiter = LogRateLimiter(initialBurst: 2, stride: 3);

      final decisions = <bool>[
        for (var i = 0; i < 8; i++) limiter.shouldLog('auth'),
      ];

      expect(decisions, <bool>[true, true, true, false, false, true, false, false]);
      expect(limiter.countFor('auth'), equals(8));
    });

    test('should keep categories isolated', () {
      final limiter = LogRateLimiter(initialBurst: 1, stride: 0);

      expect(limiter.shouldLog('a'), isTrue);
      expect(limiter.shouldLog('a'), isFalse);
      expect(limiter.shouldLog('b'), isTrue);
      expect(limiter.countFor('a'), equals(2));
      expect(limiter.countFor('b'), equals(1));
    });

    test('should respect minimum interval', () {
      var now = DateTime.utc(2026);
      final limiter = LogRateLimiter(
        initialBurst: 10,
        minimumInterval: const Duration(seconds: 5),
        clock: () => now,
      );

      expect(limiter.shouldLog('transport'), isTrue);
      now = now.add(const Duration(seconds: 2));
      expect(limiter.shouldLog('transport'), isFalse);
      now = now.add(const Duration(seconds: 3));
      expect(limiter.shouldLog('transport'), isTrue);
    });
  });
}
