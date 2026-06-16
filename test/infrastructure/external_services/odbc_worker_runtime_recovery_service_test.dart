import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_circuit_breaker.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_runtime_lifecycle.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_worker_runtime_recovery_service.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _MockConnectionPool extends Mock implements IConnectionPool {}

class _MockCircuitBreakerGateway extends Mock implements IOdbcConnectionCircuitBreaker {}

class _MockOdbcService extends Mock implements OdbcService {}

class _MockOdbcConnectionSettings extends Mock implements IOdbcConnectionSettings {}

void main() {
  group('OdbcWorkerRuntimeRecoveryService', () {
    late _MockConnectionPool connectionPool;
    late _MockCircuitBreakerGateway databaseGateway;
    late _MockCircuitBreakerGateway streamingGateway;
    late OdbcInFlightExecutionRegistry inFlightRegistry;
    late OdbcRuntimeLifecycle runtimeLifecycle;
    late OdbcStreamingGateway streamingGatewayConcrete;
    late MetricsCollector metrics;
    late OdbcWorkerRuntimeRecoveryService service;

    setUp(() {
      connectionPool = _MockConnectionPool();
      databaseGateway = _MockCircuitBreakerGateway();
      streamingGateway = _MockCircuitBreakerGateway();
      inFlightRegistry = OdbcInFlightExecutionRegistry();
      final odbcService = _MockOdbcService();
      final settings = _MockOdbcConnectionSettings();
      when(() => settings.poolSize).thenReturn(ConnectionConstants.defaultPoolSize);
      when(odbcService.initialize).thenAnswer((_) async => const Success(unit));
      runtimeLifecycle = OdbcRuntimeLifecycle(odbcService);
      metrics = MetricsCollector();
      streamingGatewayConcrete = OdbcStreamingGateway(
        odbcService,
        settings,
        runtimeLifecycle: runtimeLifecycle,
      );
      service = OdbcWorkerRuntimeRecoveryService(
        connectionPool: connectionPool,
        databaseGateway: databaseGateway,
        streamingGateway: streamingGateway,
        runtimeLifecycle: runtimeLifecycle,
        inFlightExecutionRegistry: inFlightRegistry,
        streamingGatewayConcrete: streamingGatewayConcrete,
        metrics: metrics,
      );

      when(() => connectionPool.closeAll()).thenAnswer((_) async => const Success(unit));
    });

    tearDown(() {
      metrics.dispose();
    });

    test('invalidates pools, breakers, in-flight registry, and re-initializes ODBC', () async {
      inFlightRegistry.register(
        'req-1',
        const OdbcInFlightExecutionHandle(connectionId: 'conn-1', statementId: 7),
      );

      await service.recoverAfterNativeWorkerCrash();

      verify(() => connectionPool.closeAll()).called(1);
      verify(() => databaseGateway.clearAllCircuitBreakers()).called(1);
      verify(() => streamingGateway.clearAllCircuitBreakers()).called(1);
      expect(inFlightRegistry.peek('req-1'), isNull);
      expect(runtimeLifecycle.isInitialized, isTrue);
      expect(metrics.getSnapshot()['odbc_worker_recovery_invalidation'], 1);
    });
  });
}
