import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

class _MockOdbcService extends Mock implements OdbcService {}

class _MockConnectionPool extends Mock implements IConnectionPool {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
  });

  group('OdbcGatewayConnectionManager', () {
    late _MockOdbcService service;
    late _MockConnectionPool pool;
    late MetricsCollector metrics;
    late OdbcGatewayConnectionManager manager;

    setUp(() {
      service = _MockOdbcService();
      pool = _MockConnectionPool();
      metrics = MetricsCollector()..clear();
      manager = OdbcGatewayConnectionManager(
        service: service,
        connectionPool: pool,
        directConnectionLimiter: DirectOdbcConnectionLimiter(
          maxConcurrent: 2,
          acquireTimeout: const Duration(seconds: 1),
        ),
        metrics: metrics,
      );
    });

    test('records in-flight pool discards and completes gauge on finish', () async {
      manager.markConnectionForDiscard('conn-1');
      when(() => pool.discard('conn-1')).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const Success(unit);
      });

      await manager.releaseConnectionSafely('conn-1');
      expect(manager.poolDiscardInflightCount, 1);
      expect(metrics.poolDiscardInflightCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(manager.poolDiscardInflightCount, 0);
      expect(metrics.poolDiscardInflightCount, 0);
    });

    test('reconcilePoolDiscardInflight is a no-op for fresh discards', () async {
      manager.markConnectionForDiscard('fresh-conn');
      when(() => pool.discard('fresh-conn')).thenAnswer(
        (_) => Completer<Result<void>>().future,
      );

      await manager.releaseConnectionSafely('fresh-conn');
      await manager.reconcilePoolDiscardInflight();

      expect(metrics.getSnapshot()['pool_discard_reconciliation_stale'], isNull);
      expect(manager.poolDiscardInflightCount, 1);
    });

    test('connectSafely maps thrown errors through OdbcFailureMapper', () async {
      when(
        () => service.connect(any(), options: any(named: 'options')),
      ).thenThrow(StateError('driver unavailable'));

      final result = await manager.connectSafely(
        'DSN=test',
        options: const ConnectionOptions(),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.Failure>());
    });

    test('reconcilePoolDiscardInflight re-attempts stale discards', () async {
      manager = OdbcGatewayConnectionManager(
        service: service,
        connectionPool: pool,
        directConnectionLimiter: DirectOdbcConnectionLimiter(
          maxConcurrent: 2,
          acquireTimeout: const Duration(seconds: 1),
        ),
        metrics: metrics,
        inflightDiscardStaleThreshold: Duration.zero,
      );
      manager.markConnectionForDiscard('stale-conn');
      var discardCalls = 0;
      when(() => pool.discard('stale-conn')).thenAnswer((_) async {
        discardCalls++;
        if (discardCalls == 1) {
          return Completer<Result<void>>().future;
        }
        return const Success(unit);
      });

      await manager.releaseConnectionSafely('stale-conn');
      await manager.reconcilePoolDiscardInflight();

      expect(discardCalls, 2);
      expect(metrics.getSnapshot()['pool_discard_reconciliation_stale'], 1);
      expect(metrics.getSnapshot()['pool_discard_reconciliation_remediated'], 1);
      expect(manager.poolDiscardInflightCount, 0);
    });

    test('reconcilePoolDiscardInflight force-releases when re-discard fails', () async {
      manager = OdbcGatewayConnectionManager(
        service: service,
        connectionPool: pool,
        directConnectionLimiter: DirectOdbcConnectionLimiter(
          maxConcurrent: 2,
          acquireTimeout: const Duration(seconds: 1),
        ),
        metrics: metrics,
        inflightDiscardStaleThreshold: Duration.zero,
      );
      manager.markConnectionForDiscard('force-conn');
      var discardCalls = 0;
      when(() => pool.discard('force-conn')).thenAnswer((_) async {
        discardCalls++;
        if (discardCalls == 1) {
          return Completer<Result<void>>().future;
        }
        return Failure(Exception('discard still blocked'));
      });
      when(() => service.disconnect('force-conn')).thenAnswer((_) async => const Success(unit));

      await manager.releaseConnectionSafely('force-conn');
      await manager.reconcilePoolDiscardInflight();

      verify(() => service.disconnect('force-conn')).called(1);
      expect(metrics.getSnapshot()['pool_discard_reconciliation_force_release'], 1);
      expect(manager.poolDiscardInflightCount, 0);
    });
  });
}
