import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('RetryManager', () {
    late RetryManager retryManager;

    setUp(() {
      retryManager = RetryManager.instance;
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

    group('singleton', () {
      test('should return same instance', () {
        // Act
        final instance1 = RetryManager.instance;
        final instance2 = RetryManager.instance;

        // Assert
        expect(identical(instance1, instance2), isTrue);
      });
    });
  });
}
