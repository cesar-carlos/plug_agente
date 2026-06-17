import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';

final class DeferredBootPhaseRunnerDependencies {
  const DeferredBootPhaseRunnerDependencies({
    this.runtimeStateGuard,
    this.activeConfigResolver,
    this.connectionStringSource,
    this.connectionPool,
    this.autoUpdateOrchestrator,
  });

  final AgentActionRuntimeStateGuard? runtimeStateGuard;
  final ActiveConfigResolver? activeConfigResolver;
  final IConfigConnectionStringSource? connectionStringSource;
  final IConnectionPool? connectionPool;
  final IAutoUpdateOrchestrator? autoUpdateOrchestrator;
}
