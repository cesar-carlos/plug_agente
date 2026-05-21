import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/presentation/boot/startup_auto_session_retry_policy.dart';

void main() {
  group('StartupAutoSessionRetryPolicy', () {
    test('retries transient failures until the configured limit', () {
      const policy = StartupAutoSessionRetryPolicy(maxTransientRetries: 2);
      final failure = domain_errors.NetworkFailure('hub offline');

      expect(policy.canRetry(failure, 0), isTrue);
      expect(policy.canRetry(failure, 1), isTrue);
      expect(policy.canRetry(failure, 2), isFalse);
    });

    test('does not retry terminal failures', () {
      const policy = StartupAutoSessionRetryPolicy();
      final failure = domain_errors.ValidationFailure('invalid credentials');

      expect(policy.canRetry(failure, 0), isFalse);
    });

    test('uses capped exponential backoff', () {
      const policy = StartupAutoSessionRetryPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 5),
      );

      expect(policy.delayForRetry(1), const Duration(seconds: 1));
      expect(policy.delayForRetry(2), const Duration(seconds: 2));
      expect(policy.delayForRetry(3), const Duration(seconds: 4));
      expect(policy.delayForRetry(4), const Duration(seconds: 5));
      expect(policy.delayForRetry(20), const Duration(seconds: 5));
    });
  });
}
