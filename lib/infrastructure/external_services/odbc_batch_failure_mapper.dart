import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_diagnostics_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_execution_types.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

final class OdbcBatchFailureMapper {
  const OdbcBatchFailureMapper({
    required OdbcGatewayConnectionManager connectionManager,
    required MetricsCollector metrics,
  }) : _connectionManager = connectionManager,
       _metrics = metrics;

  final OdbcGatewayConnectionManager _connectionManager;
  final MetricsCollector _metrics;

  bool shouldFallbackTransactionalNativePoolToDirect({
    required BatchExecutionContext context,
    required Object error,
    required int attempt,
  }) {
    if (!context.nativeCompatibleAcquire || context.ownedConnection || attempt > 0) {
      return false;
    }
    final failure = error is domain.Failure ? error : OdbcFailureMapper.mapQueryError(error);
    if (failure.context['operation'] == 'transaction_validation') {
      return false;
    }
    return failure is domain.ConnectionFailure ||
        queryFailureIndicatesInvalidConnectionId(failure) ||
        failure.context['connectionFailed'] == true ||
        failure.context['timeout'] == true ||
        failure.context['reason'] == OdbcContextConstants.bufferTooSmallReason ||
        failure.context['reason'] == OdbcContextConstants.odbcWorkerBusyConnectReason ||
        OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(OdbcErrorInspector.message(failure));
  }

  bool shouldFallbackReadOnlyBatchNativePool({
    required Object error,
    required int attempt,
  }) {
    if (attempt > 0) {
      return false;
    }
    final failure = error is domain.Failure ? error : OdbcFailureMapper.mapQueryError(error);
    return failure is domain.ConnectionFailure ||
        queryFailureIndicatesInvalidConnectionId(failure) ||
        failure.context['connectionFailed'] == true ||
        failure.context['timeout'] == true;
  }

  bool shouldRecoverNonTransactionalBatchConnection(domain.Failure failure) {
    if (failure is domain.ConnectionFailure) {
      return true;
    }

    if (queryFailureIndicatesInvalidConnectionId(failure)) {
      return true;
    }

    return failure.context['connectionFailed'] == true;
  }

  bool queryFailureIndicatesInvalidConnectionId(domain.Failure failure) {
    return OdbcErrorInspector.isInvalidConnectionId(failure);
  }

  void recordTransactionalNativePoolFallback({
    required BatchExecutionContext context,
    required Object error,
    required String stage,
    String? connectionId,
  }) {
    _metrics.recordTransactionalBatchNativePoolFallback();
    _metrics.recordDiagnosticReason(
      category: 'batch',
      reason: RpcSqlDiagnosticsConstants.transactionalNativePoolFallbackReason,
    );
    if (connectionId != null) {
      _connectionManager.markConnectionForDiscard(connectionId);
    }
    _connectionManager.recordPooledExecutionFailure(
      connectionString: context.connectionString,
      connectionId: connectionId,
      error: error,
      stage: stage,
    );
  }

  void recordReadOnlyBatchNativePoolFallback({
    required String connectionString,
    required Object error,
    required String stage,
  }) {
    _metrics.recordReadOnlyBatchNativePoolFallback();
    _metrics.recordDiagnosticReason(
      category: 'batch',
      reason: RpcSqlDiagnosticsConstants.readOnlyBatchNativePoolFallbackReason,
    );
    _connectionManager.recordPooledExecutionFailure(
      connectionString: connectionString,
      error: error,
      stage: 'read_only_batch_native_pool_$stage',
    );
    developer.log(
      'Read-only parallel batch falling back from native pool to lease pool',
      name: 'database_gateway',
      level: 900,
      error: {
        'stage': stage,
        'error': OdbcErrorInspector.message(error),
      },
    );
  }
}
