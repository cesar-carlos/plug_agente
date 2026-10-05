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

    test('waits for pending discard and does not return it twice', () async {
      final completion = Completer<Result<void>>();
      when(() => pool.discard('pending')).thenAnswer((_) => completion.future);
      manager.markConnectionForDiscard('pending');
      await manager.releaseConnectionSafely('pending');
      await manager.releaseConnectionSafely('pending');
      var finished = false;
      final waited = manager.waitForPendingDiscards(timeout: const Duration(seconds: 1))..then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      completion.complete(const Success(unit));
      expect((await waited).isSuccess(), isTrue);
      verify(() => pool.discard('pending')).called(1);
      verifyNever(() => pool.release('pending'));
    });

    test('cleanup timeout retains the pending resource', () async {
      final completion = Completer<Result<void>>();
      when(() => pool.discard('pending')).thenAnswer((_) => completion.future);
      manager.markConnectionForDiscard('pending');
      await manager.releaseConnectionSafely('pending');
      final result = await manager.waitForPendingDiscards(timeout: const Duration(milliseconds: 1));
      expect(result.isError(), isTrue);
      expect(manager.poolDiscardInflightCount, 1);
      completion.complete(const Success(unit));
      expect((await manager.waitForPendingDiscards(timeout: const Duration(seconds: 1))).isSuccess(), isTrue);
    });

    test('drains queued discards and isolates unknown outcomes', () async {
      manager = OdbcGatewayConnectionManager(
        service: service,
        connectionPool: pool,
        directConnectionLimiter: DirectOdbcConnectionLimiter(
          maxConcurrent: 2,
          acquireTimeout: const Duration(seconds: 1),
        ),
        metrics: metrics,
        maxInflightPoolDiscards: 1,
      );
      final first = Completer<Result<void>>();
      final second = Completer<Result<void>>();
      when(() => pool.discard('first')).thenAnswer((_) => first.future);
      when(() => pool.discard('second')).thenAnswer((_) => second.future);
      manager.markConnectionForDiscard('first');
      manager.markConnectionForDiscard('second');
      await manager.releaseConnectionSafely('first');
      await manager.releaseConnectionSafely('second');
      await manager.releaseConnectionSafely('second');
      final drained = manager.waitForPendingDiscards(timeout: const Duration(seconds: 1));
      first.complete(const Success(unit));
      await Future<void>.delayed(Duration.zero);
      verify(() => pool.discard('second')).called(1);
      verifyNever(() => pool.release('second'));
      second.complete(const Success(unit));
      expect((await drained).isSuccess(), isTrue);
      manager.markConnectionOutcomeUnknown('unknown');
      final isolated = await manager.waitForPendingDiscards(timeout: const Duration(seconds: 1));
      expect(isolated.exceptionOrNull(), isA<domain.ConnectionFailure>());
      verifyNever(() => pool.release('unknown'));
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

    test('stale discard keeps its original owner until confirmation', () async {
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
      final completion = Completer<Result<void>>();
      when(() => pool.discard('stale-conn')).thenAnswer((_) => completion.future);

      await manager.releaseConnectionSafely('stale-conn');
      await manager.reconcilePoolDiscardInflight();

      await manager.releaseConnectionSafely('stale-conn');
      verify(() => pool.discard('stale-conn')).called(1);
      verifyNever(() => service.disconnect(any()));
      expect(metrics.getSnapshot()['pool_discard_reconciliation_stale'], 1);
      expect(manager.poolDiscardInflightCount, 1);
      completion.complete(const Success(unit));
      expect((await manager.waitForPendingDiscards(timeout: const Duration(seconds: 1))).isSuccess(), isTrue);
      expect(manager.poolDiscardInflightCount, 0);
    });

    test('completed failed discard remains unconfirmed on later drains', () async {
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
      manager.markConnectionForDiscard('failed-conn');
      when(() => pool.discard('failed-conn')).thenAnswer((_) async => Failure(Exception('discard failed')));
      await manager.releaseConnectionSafely('failed-conn');
      final first = await manager.waitForPendingDiscards(timeout: const Duration(seconds: 1));
      final second = await manager.waitForPendingDiscards(timeout: const Duration(seconds: 1));
      expect(first.isError(), isTrue);
      expect(second.isError(), isTrue);
      expect((second.exceptionOrNull()! as domain.ConnectionFailure).context['cleanup_unconfirmed'], isTrue);
      verifyNever(() => service.disconnect(any()));
      verify(() => pool.discard('failed-conn')).called(1);
      expect(manager.poolDiscardInflightCount, 0);
    });
  });
}
