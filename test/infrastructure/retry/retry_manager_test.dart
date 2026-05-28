import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('RetryManager', () {
    late RetryManager retryManager;

    setUp(() {
      // Disable jitter so timing-sensitive assertions stay deterministic; the
      // dedicated jitter group below exercises non-zero factors explicitly.
      retryManager = RetryManager(jitterFactor: 0);
    });

    group('execute', () {
      test('should return success on first attempt', () async {
        // Arrange
        var attempts = 0;

        // Act
        final result = await retryManager.execute(
          () async {
            attempts++;
            return const Success('success');
          },
        );

        // Assert
        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 'success');
        expect(attempts, 1);
      });

      test('should retry on transient failure', () async {
        // Arrange
        var attempts = 0;

        // Act
        final result = await retryManager.execute<String>(
          () async {
            attempts++;
            if (attempts < 2) {
              throw domain.ConnectionFailure('Connection timeout');
            }
            return const Success('success');
          },
          initialDelayMs: 10,
        );

        // Assert
        expect(result.isSuccess(), isTrue);
        expect(attempts, 2);
      });

      test('should not retry on non-transient failure', () async {
        // Arrange
        var attempts = 0;

        // Act
        final result = await retryManager.execute<String>(
          () async {
            attempts++;
            throw domain.ValidationFailure('Invalid SQL syntax');
          },
          initialDelayMs: 10,
        );

        // Assert
        expect(result.isError(), isTrue);
        expect(attempts, 1); // Should not retry
      });

      test('should fail after max attempts', () async {
        // Arrange
        var attempts = 0;

        // Act
        final result = await retryManager.execute<String>(
          () async {
            attempts++;
            throw domain.ConnectionFailure('Connection timeout');
          },
          maxAttempts: 2,
          initialDelayMs: 10,
        );

        // Assert
        expect(result.isError(), isTrue);
        expect(attempts, 2); // Max attempts reached
      });

      test('should use exponential backoff', () async {
        // Arrange
        var attempts = 0;
        final stopwatch = Stopwatch()..start();

        // Act
        await retryManager.execute<String>(
          () async {
            attempts++;
            if (attempts < 3) {
              throw domain.ConnectionFailure('Connection timeout');
            }
            return const Success('success');
          },
          initialDelayMs: 50,
        );

        stopwatch.stop();

        // Assert
        expect(attempts, 3);
        // Should have waited: 50ms + 100ms = 150ms minimum
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(140));
      });
    });

    group('isTransientFailure', () {
      test('should identify connection timeout as transient', () {
        // Arrange
        final failure = domain.ConnectionFailure('Connection timeout');

        // Act
        final isTransient = retryManager.isTransientFailure(failure);

        // Assert
        expect(isTransient, isTrue);
      });

      test('should identify connection refused as transient', () {
        // Arrange
        final failure = domain.ConnectionFailure('Connection refused');

        // Act
        final isTransient = retryManager.isTransientFailure(failure);

        // Assert
        expect(isTransient, isTrue);
      });

      test('should identify network error as transient', () {
        // Arrange
        final failure = domain.ConnectionFailure('Network error');

        // Act
        final isTransient = retryManager.isTransientFailure(failure);

        // Assert
        expect(isTransient, isTrue);
      });

      test('should not identify validation failure as transient', () {
        // Arrange
        final failure = domain.ValidationFailure('Invalid query');

        // Act
        final isTransient = retryManager.isTransientFailure(failure);

        // Assert
        expect(isTransient, isFalse);
      });

      test('should not identify query execution failure as transient', () {
        // Arrange
        final failure = domain.QueryExecutionFailure('SQL syntax error');

        // Act
        final isTransient = retryManager.isTransientFailure(failure);

        // Assert
        expect(isTransient, isFalse);
      });

      test('should not identify retryable query execution failure as transient', () {
        // Arrange
        final failure = domain.QueryExecutionFailure.withContext(
          message: 'Lock request timeout',
          context: {'retryable': true},
        );

        // Act
        final isTransient = retryManager.isTransientFailure(failure);

        // Assert
        expect(isTransient, isFalse);
      });

      test('should not retry operation when query execution failure is retryable', () async {
        // Arrange
        var attempts = 0;

        // Act
        final result = await retryManager.execute<String>(
          () async {
            attempts++;
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Deadlock victim',
                context: {'retryable': true},
              ),
            );
          },
          initialDelayMs: 10,
        );

        // Assert
        expect(result.isError(), isTrue);
        expect(attempts, 1);
      });

      test('should not identify configuration failure as transient', () {
        // Arrange
        final failure = domain.ConfigurationFailure('Missing config');

        // Act
        final isTransient = retryManager.isTransientFailure(failure);

        // Assert
        expect(isTransient, isFalse);
      });

      test('should not identify generic exception as transient', () {
        // Arrange
        final exception = Exception('Generic error');

        // Act
        final isTransient = retryManager.isTransientFailure(exception);

        // Assert
        expect(isTransient, isFalse);
      });
    });

    group('jitter', () {
      test('should reject jitterFactor outside [0, 1]', () {
        expect(() => RetryManager(jitterFactor: -0.1), throwsA(isA<AssertionError>()));
        expect(() => RetryManager(jitterFactor: 1.1), throwsA(isA<AssertionError>()));
      });

      test('should keep delay equal to base when jitterFactor is zero', () async {
        final manager = RetryManager(jitterFactor: 0);
        var attempts = 0;
        final stopwatch = Stopwatch()..start();

        await manager.execute<String>(
          () async {
            attempts++;
            if (attempts < 3) {
              throw domain.ConnectionFailure('Connection timeout');
            }
            return const Success('success');
          },
          initialDelayMs: 60,
        );
        stopwatch.stop();

        expect(attempts, 3);
        // Without jitter: 60ms + 120ms = 180ms minimum.
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(170));
      });

      test('should keep jittered delay within ±factor band', () async {
        // Random.nextDouble() == 0 yields offset = (0*2 - 1) * span = -span,
        // which is the most aggressive negative deviation possible.
        final manager = RetryManager(
          jitterFactor: 0.5,
          random: _FixedRandom(0),
        );
        var attempts = 0;
        final stopwatch = Stopwatch()..start();

        await manager.execute<String>(
          () async {
            attempts++;
            if (attempts < 2) {
              throw domain.ConnectionFailure('Connection timeout');
            }
            return const Success('success');
          },
          initialDelayMs: 100,
        );
        stopwatch.stop();

        // With nextDouble()=0 and factor=0.5 the delay shrinks to 50ms.
        expect(attempts, 2);
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('should clamp jittered delay to at least 1ms', () async {
        // Even with a degenerate base delay the loop must still yield.
        final manager = RetryManager(
          jitterFactor: 1,
          random: _FixedRandom(0),
        );
        var attempts = 0;

        final result = await manager.execute<String>(
          () async {
            attempts++;
            if (attempts < 2) {
              throw domain.ConnectionFailure('Connection timeout');
            }
            return const Success('success');
          },
          initialDelayMs: 1,
        );

        expect(result.isSuccess(), isTrue);
        expect(attempts, 2);
      });
    });
  });
}

/// `Random` stub that always returns [_value] from `nextDouble()`. Used to make
/// jitter assertions deterministic without depending on a real RNG seed.
class _FixedRandom implements Random {
  _FixedRandom(this._value);

  final double _value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => _value;

  @override
  int nextInt(int max) => 0;
}
