import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_retry_coordinator.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:result_dart/result_dart.dart';

class _MockRetryManager extends Mock implements IRetryManager {}

void main() {
  group('OdbcGatewayRetryCoordinator', () {
    late OdbcGatewayRetryCoordinator coordinator;

    group('executeWithRetryBudget without timeout', () {
      late _MockRetryManager mockRetryManager;

      setUp(() {
        mockRetryManager = _MockRetryManager();
        coordinator = OdbcGatewayRetryCoordinator(mockRetryManager);
      });

      test('delegates to retry manager when timeout is null', () async {
        when(
          () => mockRetryManager.execute<int>(
            any(),
            maxAttempts: any(named: 'maxAttempts'),
            initialDelayMs: any(named: 'initialDelayMs'),
            backoffMultiplier: any(named: 'backoffMultiplier'),
          ),
        ).thenAnswer((_) async => const Success(42));

        final result = await coordinator.executeWithRetryBudget<int>(
          (_) async => const Success(1),
          maxAttempts: 3,
          initialDelayMs: 500,
          backoffMultiplier: 2,
          timeout: null,
          stage: 'query',
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 42);
        verify(
          () => mockRetryManager.execute<int>(
            any(),
            maxAttempts: 3,
            initialDelayMs: 500,
            backoffMultiplier: 2,
          ),
        ).called(1);
      });
    });

    group('executeWithRetryBudget with timeout', () {
      setUp(() {
        coordinator = OdbcGatewayRetryCoordinator(RetryManager(jitterFactor: 0));
      });

      test('returns success on first attempt', () async {
        var calls = 0;

        final result = await coordinator.executeWithRetryBudget<String>(
          (_) async {
            calls++;
            return const Success('ok');
          },
          maxAttempts: 3,
          initialDelayMs: 10,
          backoffMultiplier: 2,
          timeout: const Duration(seconds: 5),
          stage: 'query',
        );

        expect(result.isSuccess(), isTrue);
        expect(calls, 1);
      });

      test('retries transient failures within budget', () async {
        var calls = 0;

        final result = await coordinator.executeWithRetryBudget<String>(
          (_) async {
            calls++;
            if (calls < 2) {
              return Failure(domain.ConnectionFailure('timeout'));
            }
            return const Success('ok');
          },
          maxAttempts: 3,
          initialDelayMs: 10,
          backoffMultiplier: 2,
          timeout: const Duration(seconds: 5),
          stage: 'query',
        );

        expect(result.isSuccess(), isTrue);
        expect(calls, 2);
      });

      test('does not retry non-transient failures', () async {
        var calls = 0;

        final result = await coordinator.executeWithRetryBudget<String>(
          (_) async {
            calls++;
            return Failure(domain.ValidationFailure('bad sql'));
          },
          maxAttempts: 3,
          initialDelayMs: 10,
          backoffMultiplier: 2,
          timeout: const Duration(seconds: 5),
          stage: 'query',
        );

        expect(result.isError(), isTrue);
        expect(calls, 1);
      });

      test('returns budget exhausted failure when deadline elapsed before attempt', () async {
        final result = await coordinator.executeWithRetryBudget<String>(
          (_) async => const Success('ok'),
          maxAttempts: 3,
          initialDelayMs: 10,
          backoffMultiplier: 2,
          timeout: Duration.zero,
          stage: 'batch',
        );

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        expect(failure, isA<domain.QueryExecutionFailure>());
        expect(
          (failure! as domain.QueryExecutionFailure).context['reason'],
          OdbcContextConstants.stageBudgetExhaustedReason('batch'),
        );
      });

      test('executeQueryWithRetry forwards defaults', () async {
        final result = await coordinator.executeQueryWithRetry<int>(
          (_) async => const Success(7),
          timeout: const Duration(seconds: 2),
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 7);
      });
    });
  });
}
