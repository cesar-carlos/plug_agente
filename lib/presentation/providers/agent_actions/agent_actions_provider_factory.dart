import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_availability_checker.dart';
import 'package:plug_agente/application/actions/agent_action_subsystem_coordinator.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/use_cases/prepare_elevated_action_runner.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_provider_dependencies.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

/// Composition-root inputs for constructing [AgentActionsProvider].
final class AgentActionsProviderWiring {
  const AgentActionsProviderWiring({
    required this.dependencies,
    required this.preflightSettings,
    this.runtimeStateGuard,
    this.subsystemCoordinator,
    this.executionQueue,
    this.secretStore,
    this.elevatedRunnerReadiness,
    this.prepareElevatedActionRunner,
    this.globalStorageContext,
    this.triggerScheduler,
    this.comObjectInvocationDiagnostics,
  });

  final AgentActionsProviderDependencies dependencies;
  final AgentActionPreflightSettings preflightSettings;
  final AgentActionRuntimeStateGuard? runtimeStateGuard;
  final AgentActionSubsystemCoordinator? subsystemCoordinator;
  final ActionExecutionQueue? executionQueue;
  final IAgentActionSecretStore? secretStore;
  final ElevatedActionRunnerReadinessService? elevatedRunnerReadiness;
  final PrepareElevatedActionRunner? prepareElevatedActionRunner;
  final GlobalStorageContext? globalStorageContext;
  final AgentActionTriggerScheduler? triggerScheduler;
  final IComObjectInvocationDiagnostics? comObjectInvocationDiagnostics;
}

/// Wires [AgentActionsProvider] from composition-root dependencies.
AgentActionsProvider createAgentActionsProvider(AgentActionsProviderWiring wiring) {
  final deps = wiring.dependencies;
  return AgentActionsProvider(
    deps,
    runtimeStateGuard: wiring.runtimeStateGuard,
    subsystemCoordinator: wiring.subsystemCoordinator,
    executionQueue: wiring.executionQueue,
    secretAvailabilityChecker: AgentActionSecretAvailabilityChecker(
      secretStore: wiring.secretStore,
    ),
    saveAgentActionSecret: deps.saveAgentActionSecret,
    deleteAgentActionSecret: deps.deleteAgentActionSecret,
    elevatedRunnerReadiness: wiring.elevatedRunnerReadiness,
    prepareElevatedActionRunner: wiring.prepareElevatedActionRunner,
    globalStorageContext: wiring.globalStorageContext,
    triggerScheduler: wiring.triggerScheduler,
    comObjectInvocationDiagnostics: wiring.comObjectInvocationDiagnostics,
    preflightSettings: wiring.preflightSettings,
  );
}
