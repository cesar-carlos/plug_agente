import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';

void main() {
  group('ClientTokenGetPolicyRateLimiter', () {
    test('should allow unlimited when maxCallsPerMinute is 0', () {
      final limiter = ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0);
      expect(limiter.tryAcquire('a'), isTrue);
      expect(limiter.tryAcquire('a'), isTrue);
    });

    test('should enforce max calls per minute window', () {
      final limiter = ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 2);
      expect(limiter.tryAcquire('scope'), isTrue);
      expect(limiter.tryAcquire('scope'), isTrue);
      expect(limiter.tryAcquire('scope'), isFalse);
    });

    test('should track scopes independently', () {
      final limiter = ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 1);
      expect(limiter.tryAcquire('a'), isTrue);
      expect(limiter.tryAcquire('b'), isTrue);
    });

    test('should cap distinct scope keys to avoid unbounded map growth', () {
      final limiter = ClientTokenGetPolicyRateLimiter(
        maxCallsPerMinute: 1000,
        maxScopeEntries: 12,
        random: Random(0),
      );
      for (var i = 0; i < 200; i++) {
        limiter.tryAcquire('scope-$i');
      }
      expect(limiter.trackedScopeCount, lessThanOrEqualTo(12));
    });
  });
}
