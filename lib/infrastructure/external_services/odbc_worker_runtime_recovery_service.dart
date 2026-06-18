import 'dart:developer' as developer;

import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_circuit_breaker.dart';
import 'package:plug_agente/domain/repositories/i_odbc_worker_runtime_recovery_port.dart';
import 'package:plug_agente/domain/repositories/i_sql_execution_idle_wait_port.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_runtime_lifecycle.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

/// Invalidates pooled ODBC state after the native async worker recovers from a crash.
final class OdbcWorkerRuntimeRecoveryService implements IOdbcWorkerRuntimeRecoveryPort {
  OdbcWorkerRuntimeRecoveryService({
    required IConnectionPool connectionPool,
    required IOdbcConnectionCircuitBreaker databaseGateway,
    required IOdbcConnectionCircuitBreaker streamingGateway,
    required OdbcRuntimeLifecycle runtimeLifecycle,
    required OdbcInFlightExecutionRegistry inFlightExecutionRegistry,
    ISqlExecutionIdleWaitPort? sqlExecutionIdleWaitPort,
    OdbcStreamingGateway? streamingGatewayConcrete,
    MetricsCollector? metrics,
  }) : _connectionPool = connectionPool,
       _databaseGateway = databaseGateway,
       _streamingGateway = streamingGateway,
       _runtimeLifecycle = runtimeLifecycle,
       _inFlightExecutionRegistry = inFlightExecutionRegistry,
       _sqlExecutionIdleWaitPort = sqlExecutionIdleWaitPort,
       _streamingGatewayConcrete = streamingGatewayConcrete,
       _metrics = metrics;

  static const String _logName = 'odbc_worker_runtime_recovery';

  final IConnectionPool _connectionPool;
  final IOdbcConnectionCircuitBreaker _databaseGateway;
  final IOdbcConnectionCircuitBreaker _streamingGateway;
  final OdbcRuntimeLifecycle _runtimeLifecycle;
  final OdbcInFlightExecutionRegistry _inFlightExecutionRegistry;
  final ISqlExecutionIdleWaitPort? _sqlExecutionIdleWaitPort;
  final OdbcStreamingGateway? _streamingGatewayConcrete;
  final MetricsCollector? _metrics;

  @override
  Future<void> recoverAfterNativeWorkerCrash() async {
    _metrics?.recordOdbcWorkerRecoveryInvalidation();

    await _waitForInFlightSqlWorkers();

    await _streamingGatewayConcrete?.invalidateAfterWorkerRecovery();
    _inFlightExecutionRegistry.clearAll();
    _databaseGateway.clearAllCircuitBreakers();
    _streamingGateway.clearAllCircuitBreakers();

    final closeResult = await _connectionPool.closeAll();
    closeResult.fold(
      (_) {},
      (error) {
        developer.log(
          'Pool closeAll failed during ODBC worker recovery',
          name: _logName,
          level: 900,
          error: error,
        );
      },
    );

    _runtimeLifecycle.invalidateAfterWorkerRecovery();
    final initResult = await _runtimeLifecycle.ensureInitialized(
      operation: 'recover_odbc_after_worker_crash',
      userMessage: 'Não foi possível reinicializar o ambiente ODBC após recuperação do worker.',
    );
    initResult.fold(
      (_) {},
      (failure) {
        developer.log(
          'ODBC re-initialization failed after worker recovery',
          name: _logName,
          level: 1000,
          error: failure,
        );
      },
    );

    developer.log(
      'ODBC runtime invalidated after native worker recovery',
      name: _logName,
      level: 900,
    );
  }

  Future<void> _waitForInFlightSqlWorkers() async {
    final idleWaitPort = _sqlExecutionIdleWaitPort;
    if (idleWaitPort == null) {
      return;
    }

    final waitResult = await idleWaitPort.waitForActiveWorkers();
    waitResult.fold(
      (_) {},
      (failure) {
        developer.log(
          'SQL execution queue did not drain before ODBC worker recovery; proceeding to pool close',
          name: _logName,
          level: 900,
          error: failure,
        );
      },
    );
  }
}
