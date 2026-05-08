import 'package:flutter_test/flutter_test.dart';
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
              'reason': 'pool_wait_timeout',
            },
          ),
        ),
      );

      expect(result.isError(), isTrue);
      expect(breaker.state, CircuitState.closed);
      expect(breaker.consecutiveFailures, 0);
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
  });
}
