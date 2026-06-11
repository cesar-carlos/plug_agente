import 'package:plug_agente/application/rpc/sql_batch_handler.dart';

import 'package:plug_agente/application/rpc/sql_bulk_insert_handler.dart';

import 'package:plug_agente/application/rpc/sql_cancel_handler.dart';

import 'package:plug_agente/application/rpc/sql_db_streaming_auto_policy.dart';

import 'package:plug_agente/application/rpc/sql_execute_handler.dart';

import 'package:plug_agente/application/rpc/sql_rpc_client_token_gate.dart';

import 'package:plug_agente/application/rpc/sql_rpc_db_streaming_executor.dart';

import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';

import 'package:plug_agente/application/rpc/sql_rpc_materialized_streaming_executor.dart';

import 'package:plug_agente/application/rpc/sql_rpc_negotiated_capabilities.dart';

import 'package:plug_agente/application/rpc/sql_rpc_odbc_budget_runner.dart';

import 'package:plug_agente/application/rpc/sql_rpc_stream_terminal_emitter.dart';

import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';

import 'package:plug_agente/application/services/active_config_metadata_cache.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';

import 'package:plug_agente/application/services/query_normalizer_service.dart';

import 'package:plug_agente/application/use_cases/execute_sql_batch.dart';

import 'package:plug_agente/core/config/feature_flags.dart';

import 'package:plug_agente/domain/protocol/protocol.dart';

import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';

import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';

import 'package:plug_agente/domain/repositories/i_database_gateway.dart';

import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';

import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';

import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';

import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';

import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';

import 'package:uuid/uuid.dart';

class SqlRpcMethodHandlerOperations {
  SqlRpcMethodHandlerOperations({
    required IDatabaseGateway databaseGateway,

    required QueryNormalizerService normalizerService,

    required Uuid uuid,

    required FeatureFlags featureFlags,

    required SqlRpcMethodHandlerSupport support,

    ActiveConfigResolver? activeConfigResolver,

    IAgentConfigRepository? configRepository,

    IAuthorizationMetricsCollector? authMetrics,

    IDeprecationMetricsCollector? deprecationMetrics,

    IRpcDispatchMetricsCollector? dispatchMetrics,

    ISqlInvestigationCollector? sqlInvestigation,

    IStreamingDatabaseGateway? streamingGateway,

    Duration sqlExecuteTotalBudget = _defaultSqlExecuteTotalBudget,

    Duration sqlBatchTotalBudget = _defaultSqlBatchTotalBudget,

    Duration queryStageBudget = _defaultQueryStageBudget,

    Duration batchExecutionStageBudget = _defaultBatchExecutionStageBudget,

    SqlStreamingCoordinator? sqlStreamingCoordinator,

    IOdbcConnectionSettings? odbcConnectionSettings,
  }) : _sqlStreamingCoordinator =
           sqlStreamingCoordinator ??
           SqlStreamingCoordinator(
             gateway: streamingGateway,

             metrics: dispatchMetrics,
           ) {
    final clientTokenGate = SqlRpcClientTokenGate(
      featureFlags: featureFlags,

      support: support,

      authMetrics: authMetrics,

      sqlInvestigation: sqlInvestigation,
    );

    final executeSqlBatch = ExecuteSqlBatch(
      databaseGateway,

      normalizerService,

      poolSizeProvider: odbcConnectionSettings == null ? null : () => odbcConnectionSettings.poolSize,
    );

    final odbcBudgetRunner = SqlRpcOdbcBudgetRunner(
      databaseGateway: databaseGateway,

      support: support,

      queryStageBudget: queryStageBudget,

      batchExecutionStageBudget: batchExecutionStageBudget,
    );

    final streamTerminalEmitter = SqlRpcStreamTerminalEmitter(
      dispatchMetrics: dispatchMetrics,
    );

    final dbStreamingAutoPolicy = SqlDbStreamingAutoPolicy();

    final activeConfigMetadataCache = (activeConfigResolver != null || configRepository != null)
        ? ActiveConfigMetadataCache(
            activeConfigResolver: activeConfigResolver,
            legacyRepository: configRepository,
          )
        : null;

    final dbStreamingExecutor = SqlRpcDbStreamingExecutor(
      featureFlags: featureFlags,

      support: support,

      sqlStreamingCoordinator: _sqlStreamingCoordinator,

      autoPolicy: dbStreamingAutoPolicy,

      terminalEmitter: streamTerminalEmitter,

      uuid: uuid,

      sqlExecuteTotalBudget: sqlExecuteTotalBudget,

      activeConfigResolver: activeConfigResolver,

      activeConfigMetadataCache: activeConfigMetadataCache,

      configRepository: configRepository,

      streamingGateway: streamingGateway,

      dispatchMetrics: dispatchMetrics,

      odbcConnectionSettings: odbcConnectionSettings,
    );

    final materializedStreamingExecutor = SqlRpcMaterializedStreamingExecutor(
      terminalEmitter: streamTerminalEmitter,

      dispatchMetrics: dispatchMetrics,
    );

    _executeHandler = SqlExecuteHandler(
      normalizerService: normalizerService,

      uuid: uuid,

      featureFlags: featureFlags,

      support: support,

      clientTokenGate: clientTokenGate,

      odbcBudgetRunner: odbcBudgetRunner,

      dbStreamingExecutor: dbStreamingExecutor,

      materializedStreamingExecutor: materializedStreamingExecutor,

      sqlExecuteTotalBudget: sqlExecuteTotalBudget,

      deprecationMetrics: deprecationMetrics,

      dispatchMetrics: dispatchMetrics,
    );

    _batchHandler = SqlBatchHandler(
      featureFlags: featureFlags,

      support: support,

      clientTokenGate: clientTokenGate,

      uuid: uuid,

      executeSqlBatch: executeSqlBatch,

      sqlBatchTotalBudget: sqlBatchTotalBudget,

      batchExecutionStageBudget: batchExecutionStageBudget,

      supportsPageOffsetPagination: supportsPageOffsetPagination,
    );

    _bulkInsertHandler = SqlBulkInsertHandler(
      featureFlags: featureFlags,

      support: support,

      clientTokenGate: clientTokenGate,

      uuid: uuid,

      odbcBudgetRunner: odbcBudgetRunner,

      sqlBatchTotalBudget: sqlBatchTotalBudget,
    );

    _cancelHandler = SqlCancelHandler(
      featureFlags: featureFlags,

      support: support,

      sqlStreamingCoordinator: _sqlStreamingCoordinator,

      streamingGateway: streamingGateway,
    );
  }

  final SqlStreamingCoordinator _sqlStreamingCoordinator;

  late final SqlExecuteHandler _executeHandler;

  late final SqlBatchHandler _batchHandler;

  late final SqlBulkInsertHandler _bulkInsertHandler;

  late final SqlCancelHandler _cancelHandler;

  SqlStreamingCoordinator get sqlStreamingCoordinator => _sqlStreamingCoordinator;

  static const _defaultSqlExecuteTotalBudget = Duration(seconds: 35);

  static const _defaultSqlBatchTotalBudget = Duration(seconds: 45);

  static const _defaultQueryStageBudget = Duration(seconds: 30);

  static const _defaultBatchExecutionStageBudget = Duration(seconds: 35);

  Future<RpcResponse> handleSqlExecute(
    RpcRequest request,

    String agentId,

    String? clientToken, {

    required TransportLimits limits,

    required Map<String, dynamic> negotiatedExtensions,

    IRpcStreamEmitter? streamEmitter,
  }) => _executeHandler.handleSqlExecute(
    request,

    agentId,

    clientToken,

    limits: limits,

    negotiatedExtensions: negotiatedExtensions,

    streamEmitter: streamEmitter,
  );

  Future<RpcResponse> handleSqlExecuteBatch(
    RpcRequest request,

    String agentId,

    String? clientToken, {

    required TransportLimits limits,

    required Map<String, dynamic> negotiatedExtensions,
  }) => _batchHandler.handleSqlExecuteBatch(
    request,

    agentId,

    clientToken,

    limits: limits,

    negotiatedExtensions: negotiatedExtensions,
  );

  Future<RpcResponse> handleSqlBulkInsert(
    RpcRequest request,

    String? clientToken, {

    required TransportLimits limits,
  }) => _bulkInsertHandler.handleSqlBulkInsert(
    request,

    clientToken,

    limits: limits,
  );

  Future<RpcResponse> handleSqlCancel(RpcRequest request) => _cancelHandler.handleSqlCancel(request);
}
