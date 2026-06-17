import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_rpc_method_handler_operations.dart';
import 'package:plug_agente/application/rpc/sql_streaming_connection_string_cache.dart';
import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/repositories/i_active_config_query_cache.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/i_streaming_named_parameter_preparer.dart';
import 'package:uuid/uuid.dart';

class SqlRpcMethodHandlerOperationsFactory {
  const SqlRpcMethodHandlerOperationsFactory(this._streamingNamedParameterPreparer);

  final IStreamingNamedParameterPreparer _streamingNamedParameterPreparer;

  SqlRpcMethodHandlerOperations create({
    required IDatabaseGateway databaseGateway,
    required QueryNormalizerService normalizerService,
    required Uuid uuid,
    required FeatureFlags featureFlags,
    required SqlRpcMethodHandlerSupport support,
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? configRepository,
    IActiveConfigQueryCache? configQueryCache,
    SqlStreamingConnectionStringCache? streamingConnectionStringCache,
    IConfigConnectionStringSource? connectionStringSource,
    IAuthorizationMetricsCollector? authMetrics,
    IDeprecationMetricsCollector? deprecationMetrics,
    IRpcDispatchMetricsCollector? dispatchMetrics,
    ISqlInvestigationCollector? sqlInvestigation,
    IStreamingDatabaseGateway? streamingGateway,
    Duration sqlExecuteTotalBudget = const Duration(seconds: 35),
    Duration sqlBatchTotalBudget = const Duration(seconds: 45),
    Duration queryStageBudget = const Duration(seconds: 30),
    Duration batchExecutionStageBudget = const Duration(seconds: 35),
    SqlStreamingCoordinator? sqlStreamingCoordinator,
    IOdbcConnectionSettings? odbcConnectionSettings,
    ISqlInFlightExecutionAbortPort? inFlightAbortPort,
  }) {
    return SqlRpcMethodHandlerOperations(
      databaseGateway: databaseGateway,
      normalizerService: normalizerService,
      uuid: uuid,
      featureFlags: featureFlags,
      support: support,
      activeConfigResolver: activeConfigResolver,
      configRepository: configRepository,
      configQueryCache: configQueryCache,
      streamingConnectionStringCache: streamingConnectionStringCache,
      connectionStringSource: connectionStringSource,
      authMetrics: authMetrics,
      deprecationMetrics: deprecationMetrics,
      dispatchMetrics: dispatchMetrics,
      sqlInvestigation: sqlInvestigation,
      streamingGateway: streamingGateway,
      sqlExecuteTotalBudget: sqlExecuteTotalBudget,
      sqlBatchTotalBudget: sqlBatchTotalBudget,
      queryStageBudget: queryStageBudget,
      batchExecutionStageBudget: batchExecutionStageBudget,
      sqlStreamingCoordinator: sqlStreamingCoordinator,
      odbcConnectionSettings: odbcConnectionSettings,
      inFlightAbortPort: inFlightAbortPort,
      streamingNamedParameterPreparer: _streamingNamedParameterPreparer,
    );
  }
}
