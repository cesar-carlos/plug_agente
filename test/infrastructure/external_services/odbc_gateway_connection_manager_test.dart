import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

class _MockOdbcService extends Mock implements OdbcService {}

class _MockConnectionPool extends Mock implements IConnectionPool {}

void main() {
  group('OdbcGatewayConnectionManager', () {
    late _MockOdbcService service;
    late _MockConnectionPool pool;
    late MetricsCollector metrics;
    late DirectOdbcConnectionLimiter directLimiter;
    late OdbcGatewayConnectionManager manager;

    setUp(() {
      service = _MockOdbcService();
      pool = _MockConnectionPool();
      metrics = MetricsCollector()..clear();
      directLimiter = DirectOdbcConnectionLimiter(
        maxConcurrent: 1,
        acquireTimeout: const Duration(seconds: 1),
        metricsCollector: metrics,
      );
      manager = OdbcGatewayConnectionManager(
        service: service,
        connectionPool: pool,
        directConnectionLimiter: directLimiter,
        metrics: metrics,
      );
    });

    test('should return pool timeout failure when acquire deadline is exhausted', () async {
      final result = await manager.acquirePooledConnection(
        'dsn',
        deadline: DateTime.now().subtract(const Duration(milliseconds: 1)),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.context['reason'], equals(OdbcContextConstants.poolWaitTimeoutReason));
      expect(metrics.poolAcquireTimeoutCount, equals(1));
    });

    test('should return direct timeout failure when direct lease deadline is exhausted', () async {
      final result = await manager.acquireDirectLease(
        operation: 'query_direct',
        deadline: DateTime.now().subtract(const Duration(milliseconds: 1)),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.context['reason'], equals(OdbcContextConstants.directConnectionLimitTimeoutReason));
      expect(metrics.directConnectionAcquireTimeoutCount, equals(1));
    });

    test('should discard marked pooled connection instead of releasing it', () async {
      when(() => pool.discard('conn-1')).thenAnswer((_) async => const Success(unit));

      manager.markConnectionForDiscard('conn-1');
      await manager.releaseConnectionSafely('conn-1');
      await Future<void>.delayed(Duration.zero);

      verify(() => pool.discard('conn-1')).called(1);
      verifyNever(() => pool.release(any()));
    });

    test('should release direct lease after disconnecting owned connection', () async {
      when(() => service.disconnect('conn-1')).thenAnswer((_) async => const Success(unit));
      final lease = (await manager.acquireDirectLease(
        operation: 'query_direct',
        deadline: DateTime.now().add(const Duration(seconds: 1)),
      )).getOrThrow();

      expect(metrics.activeDirectConnections, equals(1));

      await manager.disconnectOwnedConnectionAndReleaseLease(
        connectionId: 'conn-1',
        directLease: lease,
        operation: 'query_direct_disconnect',
      );

      expect(metrics.activeDirectConnections, equals(0));
      verify(() => service.disconnect('conn-1')).called(1);
    });

    test('should rate limit pool recycle attempts for same connection string', () async {
      when(() => pool.getActiveCount(connectionString: 'dsn')).thenAnswer((_) async => const Success(0));
      when(() => pool.recycle('dsn')).thenAnswer((_) async => const Success(unit));

      await manager.tryRecoverPoolAfterInvalidConnectionId('dsn');
      await manager.tryRecoverPoolAfterInvalidConnectionId('dsn');

      verify(() => pool.getActiveCount(connectionString: 'dsn')).called(1);
      verify(() => pool.recycle('dsn')).called(1);
      expect(metrics.poolRecycleCount, equals(1));
    });
  });
}
