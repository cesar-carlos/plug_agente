import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('ConnectionCircuitBreaker', () {
    test('should not open circuit for local pool pressure failures', () async {
      final breaker = ConnectionCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 30),
      );

      final result = await breaker.execute<int>(
        'DSN=test',
        () async => Failure(
          domain.ConnectionFailure.withContext(
            message: 'Pool de conexoes ODBC esgotado',
            context: {
              'poolExhausted': true,
              'reason': OdbcContextConstants.poolWaitTimeoutReason,
            },
          ),
        ),
      );

      expect(result.isError(), isTrue);
      expect(breaker.state, CircuitState.closed);
      expect(breaker.consecutiveFailures, 0);
    });

    test('should not open circuit for authentication failures', () async {
      final breaker = ConnectionCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 30),
      );

      final result = await breaker.execute<int>(
        'DSN=test',
        () async => Failure(
          domain.ConnectionFailure.withContext(
            message: 'Database authentication failed',
            context: {
              'connectionFailed': true,
              'reason': OdbcContextConstants.authenticationFailedReason,
            },
          ),
        ),
      );

      expect(result.isError(), isTrue);
      expect(breaker.state, CircuitState.closed);
      expect(breaker.consecutiveFailures, 0);
    });

    test('should mark circuit breaker open failures as non-retryable', () async {
      final breaker = ConnectionCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 30),
      );

      await breaker.execute<int>(
        'DSN=test',
        () async => Failure(
          domain.ConnectionFailure.withContext(
            message: 'Server unreachable',
            context: {'connectionFailed': true, 'reason': 'server_unreachable'},
          ),
        ),
      );

      final openResult = await breaker.execute<int>('DSN=test', () async => const Success(1));
      final failure = openResult.exceptionOrNull()! as domain.ConnectionFailure;

      expect(failure.context['reason'], OdbcContextConstants.circuitBreakerOpenReason);
      expect(failure.context['retryable'], isFalse);
      expect(failure.isTransient, isFalse);
    });

    test('rejects concurrent callers while half-open probe is in progress', () async {
      final breaker = ConnectionCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 50),
      );

      await breaker.execute<int>(
        'DSN=test',
        () async => Failure(
          domain.ConnectionFailure.withContext(
            message: 'Server unreachable',
            context: {
              'connectionFailed': true,
              'reason': 'server_unreachable',
            },
          ),
        ),
      );
      expect(breaker.state, CircuitState.open);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      final probeGate = Completer<void>();
      final probeFuture = breaker.execute<int>(
        'DSN=test',
        () async {
          await probeGate.future;
          return const Success(1);
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(breaker.state, CircuitState.halfOpen);

      final concurrentResult = await breaker.execute<int>(
        'DSN=test',
        () async => const Success(99),
      );

      expect(concurrentResult.isError(), isTrue);
      final failure = concurrentResult.exceptionOrNull()! as domain.ConnectionFailure;
      expect(failure.context['reason'], OdbcContextConstants.circuitBreakerOpenReason);
      expect(failure.message, contains('half-open probe already in progress'));

      probeGate.complete();
      final probeResult = await probeFuture;
      expect(probeResult.isSuccess(), isTrue);
      expect(breaker.state, CircuitState.closed);
    });

    test('should open circuit for real connection failures', () async {
      final breaker = ConnectionCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 30),
      );

      final result = await breaker.execute<int>(
        'DSN=test',
        () async => Failure(
          domain.ConnectionFailure.withContext(
            message: 'Nao foi possivel alcancar o servidor de banco de dados',
            context: {
              'connectionFailed': true,
              'reason': 'server_unreachable',
            },
          ),
        ),
      );

      expect(result.isError(), isTrue);
      expect(breaker.state, CircuitState.open);
      expect(breaker.consecutiveFailures, 1);
    });

    test('should open circuit for connection failures during query execution', () async {
      final breaker = ConnectionCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 30),
      );

      final result = await breaker.execute<int>(
        'DSN=test',
        () async => Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'Connection lost while executing SQL',
            context: {
              'connectionFailed': true,
              'reason': 'connection_lost_during_query',
            },
          ),
        ),
      );

      expect(result.isError(), isTrue);
      expect(breaker.state, CircuitState.open);
      expect(breaker.consecutiveFailures, 1);
    });

    test('should not open circuit for query timeout failures', () async {
      final breaker = ConnectionCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 30),
      );

      final result = await breaker.execute<int>(
        'DSN=test',
        () async => Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'Tempo limite excedido durante a execucao da consulta',
            context: {
              'timeout': true,
              'timeout_stage': 'sql',
              'reason': 'query_timeout',
            },
          ),
        ),
      );

      expect(result.isError(), isTrue);
      expect(breaker.state, CircuitState.closed);
      expect(breaker.consecutiveFailures, 0);
    });

    group('open-state log throttling', () {
      test('should count fast-fail rejections while circuit stays open', () async {
        final breaker = ConnectionCircuitBreaker(
          failureThreshold: 1,
          resetTimeout: const Duration(seconds: 30),
        );

        await breaker.execute<int>(
          'DSN=test',
          () async => Failure(
            domain.ConnectionFailure.withContext(
              message: 'Server unreachable',
              context: {'connectionFailed': true, 'reason': 'server_unreachable'},
            ),
          ),
        );
        expect(breaker.state, CircuitState.open);
        expect(breaker.openStateRejectionCount, 0);

        for (var i = 0; i < 5; i++) {
          await breaker.execute<int>('DSN=test', () async => const Success(1));
        }

        expect(breaker.openStateRejectionCount, 5);
      });

      test('should reset rejection count when circuit closes via reset()', () async {
        final breaker = ConnectionCircuitBreaker(
          failureThreshold: 1,
          resetTimeout: const Duration(seconds: 30),
        );

        await breaker.execute<int>(
          'DSN=test',
          () async => Failure(
            domain.ConnectionFailure.withContext(
              message: 'Server unreachable',
              context: {'connectionFailed': true, 'reason': 'server_unreachable'},
            ),
          ),
        );
        await breaker.execute<int>('DSN=test', () async => const Success(1));
        await breaker.execute<int>('DSN=test', () async => const Success(1));
        expect(breaker.openStateRejectionCount, 2);

        breaker.reset();

        expect(breaker.openStateRejectionCount, 0);
        expect(breaker.state, CircuitState.closed);
      });

      test('should reset rejection count when transitioning to half-open', () async {
        final breaker = ConnectionCircuitBreaker(
          failureThreshold: 1,
          resetTimeout: const Duration(milliseconds: 30),
        );

        await breaker.execute<int>(
          'DSN=test',
          () async => Failure(
            domain.ConnectionFailure.withContext(
              message: 'Server unreachable',
              context: {'connectionFailed': true, 'reason': 'server_unreachable'},
            ),
          ),
        );
        await breaker.execute<int>('DSN=test', () async => const Success(1));
        await breaker.execute<int>('DSN=test', () async => const Success(1));
        expect(breaker.openStateRejectionCount, 2);

        await Future<void>.delayed(const Duration(milliseconds: 40));

        // After reset timeout the next call transitions to half-open and runs
        // the probe; whether it then closes depends on the operation result.
        await breaker.execute<int>('DSN=test', () async => const Success(1));

        expect(breaker.openStateRejectionCount, 0);
        expect(breaker.state, CircuitState.closed);
      });

      test('should reject custom log stride that is not positive', () {
        expect(
          () => ConnectionCircuitBreaker(
            failureThreshold: 1,
            resetTimeout: const Duration(seconds: 30),
            openStateLogStride: 0,
          ),
          throwsA(isA<AssertionError>()),
        );
      });
    });
  });
}
