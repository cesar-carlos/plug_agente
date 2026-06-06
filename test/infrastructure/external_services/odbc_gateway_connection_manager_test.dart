import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
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
  });
}
