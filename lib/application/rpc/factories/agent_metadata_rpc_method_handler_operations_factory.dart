import 'package:plug_agente/application/rpc/agent_metadata_rpc_method_handler_operations.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_odbc_diagnostics_snapshot_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';

class AgentMetadataRpcMethodHandlerOperationsFactory {
  const AgentMetadataRpcMethodHandlerOperationsFactory();

  AgentMetadataRpcMethodHandlerOperations create({
    required HealthService healthService,
    required GetClientTokenPolicy getClientTokenPolicy,
    required ClientTokenGetPolicyRateLimiter getPolicyRateLimiter,
    required FeatureFlags featureFlags,
    required AgentMetadataRpcMethodHandlerSupport support,
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? configRepository,
    IRpcDispatchMetricsCollector? dispatchMetrics,
    IOdbcDiagnosticsSnapshotCollector? odbcNativeMetricsService,
    Duration authorizationStageBudget = const Duration(seconds: 3),
  }) {
    return AgentMetadataRpcMethodHandlerOperations(
      healthService: healthService,
      getClientTokenPolicy: getClientTokenPolicy,
      getPolicyRateLimiter: getPolicyRateLimiter,
      featureFlags: featureFlags,
      support: support,
      activeConfigResolver: activeConfigResolver,
      configRepository: configRepository,
      dispatchMetrics: dispatchMetrics,
      odbcNativeMetricsService: odbcNativeMetricsService,
      authorizationStageBudget: authorizationStageBudget,
    );
  }
}
