import 'dart:developer' as developer;

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/external_services/direct_odbc_query_executor.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_execution_investigation_recorder.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_execution_policies.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/pooled_odbc_query_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

/// Pooled and direct ODBC query execution after config/retry resolution.
class OdbcQueryExecutionOrchestrator {
  OdbcQueryExecutionOrchestrator({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcQueryRunner queryRunner,
    required OdbcConnectionOptionsResolver optionsResolver,
    required NativeCompatibleAcquirePolicy nativeCompatiblePolicy,
    required MetricsCollector metrics,
    FeatureFlags? featureFlags,
    ISqlInvestigationCollector? sqlInvestigation,
  }) : _optionsResolver = optionsResolver,
       _nativeCompatiblePolicy = nativeCompatiblePolicy,
       _featureFlags = featureFlags,
       _investigationRecorder = OdbcQueryExecutionInvestigationRecorder(
         featureFlags: featureFlags,
         sqlInvestigation: sqlInvestigation,
       ) {
    final investigationRecorder = _investigationRecorder;
    _directExecutor = DirectOdbcQueryExecutor(
      connectionManager: connectionManager,
      queryRunner: queryRunner,
      optionsResolver: optionsResolver,
      metrics: metrics,
      investigationRecorder: investigationRecorder,
    );
    _pooledExecutor = PooledOdbcQueryExecutor(
      connectionManager: connectionManager,
      queryRunner: queryRunner,
      optionsResolver: optionsResolver,
      nativeCompatiblePolicy: nativeCompatiblePolicy,
      metrics: metrics,
      directExecutor: _directExecutor,
      investigationRecorder: investigationRecorder,
    );
  }

  final OdbcConnectionOptionsResolver _optionsResolver;
  final NativeCompatibleAcquirePolicy _nativeCompatiblePolicy;
  final FeatureFlags? _featureFlags;
  final OdbcQueryExecutionInvestigationRecorder _investigationRecorder;
  late final DirectOdbcQueryExecutor _directExecutor;
  late final PooledOdbcQueryExecutor _pooledExecutor;

  Future<Result<QueryResponse>> execute(
    QueryRequest request,
    String connectionString,
    DatabaseConfig databaseConfig, {
    Duration? timeout,
    CancellationToken? cancellationToken,
  }) async {
    final cancelled = OdbcQueryExecutionPolicies.cooperativeCancelFailure(
      request: request,
      cancellationToken: cancellationToken,
    );
    if (cancelled != null) {
      return Failure(cancelled);
    }

    final stopwatch = Stopwatch()..start();
    final paginationValidation = OdbcGatewayQueryPreparation.validatePaginationForDatabase(
      request,
      databaseConfig.databaseType,
    );
    if (paginationValidation != null) {
      return Failure(paginationValidation);
    }

    final preparedExecution = OdbcGatewayQueryPreparation.prepareQueryExecution(
      request,
      databaseConfig,
    );
    final queryValidation = OdbcGatewayQueryPreparation.validateQueryExecutionMode(
      request,
      preparedExecution,
    );
    if (queryValidation != null) {
      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: queryValidation.message,
        executedInDb: false,
      );
      return Failure(queryValidation);
    }
    OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
      featureFlags: _featureFlags,
      request: request,
      databaseConfig: databaseConfig,
      preparedExecution: preparedExecution,
    );

    final baseOptions = _optionsResolver.forTimeout(timeout);
    final hintedOptions = _optionsResolver.hintedFor(
      connectionString: connectionString,
      sql: preparedExecution.sql,
      baseOptions: baseOptions,
    );
    if (hintedOptions != null) {
      developer.log(
        'Using cached adaptive buffer hint for pooled query execution',
        name: 'database_gateway',
        level: 800,
      );
      return _pooledExecutor.execute(
        request,
        connectionString,
        stopwatch,
        preparedExecution: preparedExecution,
        timeout: timeout,
        acquireOptions: hintedOptions,
        cancellationToken: cancellationToken,
        databaseType: databaseConfig.databaseType,
      );
    }

    return _pooledExecutor.execute(
      request,
      connectionString,
      stopwatch,
      preparedExecution: preparedExecution,
      timeout: timeout,
      allowNativeCompatibleAcquire: _nativeCompatiblePolicy.shouldUseAcquire(
        databaseType: databaseConfig.databaseType,
        request: request,
        preparedExecution: preparedExecution,
        acquireOptions: null,
        timeout: timeout,
        defaultQueryTimeout: ConnectionConstants.defaultQueryTimeout,
        connectionString: connectionString,
      ),
      cancellationToken: cancellationToken,
      databaseType: databaseConfig.databaseType,
    );
  }

  void _recordSqlInvestigationExecutionFailure({
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required String errorMessage,
    required bool executedInDb,
    String method = 'sql.execute',
  }) {
    _investigationRecorder.recordExecutionFailure(
      request: request,
      preparedExecution: preparedExecution,
      errorMessage: errorMessage,
      executedInDb: executedInDb,
      method: method,
    );
  }
}
