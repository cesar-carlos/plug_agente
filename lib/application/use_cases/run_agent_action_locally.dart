import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_dangerous_command_policy_enforcer.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_execution_gate_chain.dart';
import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/application/actions/agent_action_execution_orchestrator.dart';
import 'package:plug_agente/application/actions/agent_action_prepared_execution_cache.dart';
import 'package:plug_agente/application/actions/agent_action_remote_lifecycle_audit_recorder.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_execution_validator.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_request_validator.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/actions/elevated_agent_action_execution_service.dart';
import 'package:plug_agente/application/use_cases/notify_agent_action_execution_if_configured.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class RunAgentActionLocally {
  RunAgentActionLocally(
    IAgentActionRepository repository,
    AgentActionLocalRunnerRegistry runnerRegistry,
    Uuid uuid, {
    ActionExecutionQueue? executionQueue,
    AgentActionRuntimeRequestValidator? runtimeRequestValidator,
    AgentActionRuntimeExecutionValidator? runtimeExecutionValidator,
    AgentActionRuntimeStateGuard? runtimeStateGuard,
    FeatureFlags? featureFlags,
    SaveAgentActionExecution? saveExecution,
    AgentRuntimeIdentity? runtimeIdentity,
    AgentActionExecutionMetricsCollector? metrics,
    AgentOperationalProfileResolver? operationalProfileResolver,
    NotifyAgentActionExecutionIfConfigured? notifyExecution,
    AgentActionSecretPlaceholderResolver? secretPlaceholderResolver,
    AgentActionAdapterRegistry? adapterRegistry,
    ElevatedActionRunnerReadinessService? elevatedRunnerReadiness,
    ElevatedAgentActionExecutionService? elevatedExecutionService,
    AgentActionRemoteLifecycleAuditRecorder? remoteLifecycleAudit,
    AgentActionDefinitionSnapshotter? definitionSnapshotter,
    AgentActionSecretReferenceFingerprinter? secretReferenceFingerprinter,
    AgentActionDangerousCommandPolicyEnforcer? dangerousCommandPolicyEnforcer,
    AgentActionExecutionGateChain? executionGateChain,
    AgentActionExecutionOrchestrator? executionOrchestrator,
    AgentActionPreparedExecutionCache? preparedExecutionCache,
    DateTime Function()? now,
  }) : _metrics = metrics,
       _adapterRegistry = adapterRegistry,
       _executionGateChain =
           executionGateChain ??
           AgentActionExecutionGateChain(
             repository: repository,
             runnerRegistry: runnerRegistry,
             runtimeRequestValidator: runtimeRequestValidator,
             runtimeExecutionValidator: runtimeExecutionValidator,
             runtimeStateGuard: runtimeStateGuard,
             featureFlags: featureFlags,
             operationalProfileResolver: operationalProfileResolver,
             secretPlaceholderResolver: secretPlaceholderResolver,
             dangerousCommandPolicyEnforcer: dangerousCommandPolicyEnforcer,
             elevatedRunnerReadiness: elevatedRunnerReadiness,
             elevatedExecutionService: elevatedExecutionService,
             definitionSnapshotter: definitionSnapshotter,
             secretReferenceFingerprinter: secretReferenceFingerprinter,
           ),
       _executionOrchestrator =
           executionOrchestrator ??
           AgentActionExecutionOrchestrator(
             repository,
             uuid,
             executionQueue: executionQueue,
             saveExecution: saveExecution ?? SaveAgentActionExecution(repository),
             runtimeIdentity: runtimeIdentity,
             metrics: metrics,
             notifyExecution: notifyExecution,
             secretPlaceholderResolver: secretPlaceholderResolver,
             elevatedExecutionService: elevatedExecutionService,
             remoteLifecycleAudit: remoteLifecycleAudit,
             runtimeStateGuard: runtimeStateGuard,
             preparedExecutionCache: preparedExecutionCache ?? AgentActionPreparedExecutionCache(),
             now: now,
           );

  final AgentActionExecutionMetricsCollector? _metrics;
  final AgentActionAdapterRegistry? _adapterRegistry;
  final AgentActionExecutionGateChain _executionGateChain;
  final AgentActionExecutionOrchestrator _executionOrchestrator;

  Future<Result<AgentActionExecution>> call(
    AgentActionExecutionRequest request,
  ) async {
    final gateResult = await _executionGateChain.evaluate(
      request: request,
      onAuthorizationDenied: _recordLocalAuthorizationDenied,
    );
    if (gateResult.isError()) {
      return Failure(gateResult.exceptionOrNull()!);
    }

    return _executionOrchestrator.run(
      gatedContext: gateResult.getOrThrow(),
      request: request,
    );
  }

  /// Validates that a remote run would pass the same gates as [call] up to queue admission,
  /// without persisting an execution or starting a process.
  Future<Result<AgentActionValidateRunSummary>> validateRemoteRun(
    AgentActionExecutionRequest request,
  ) async {
    final gateResult = await _executionGateChain.evaluate(
      request: request,
      onAuthorizationDenied: _recordLocalAuthorizationDenied,
    );
    if (gateResult.isError()) {
      return Failure(gateResult.exceptionOrNull()!);
    }

    final adapterRegistry = _adapterRegistry;
    return _executionOrchestrator.validateRemoteAdmission(
      gatedContext: gateResult.getOrThrow(),
      request: request,
      adapterPrepareCheck: adapterRegistry == null
          ? null
          : ({
              required AgentActionDefinition definition,
              required AgentActionExecutionRequest request,
            }) {
              return _executionGateChain.evaluateAdapterPrepare(
                definition: definition,
                request: request,
                adapterRegistry: adapterRegistry,
              );
            },
    );
  }

  void _recordLocalAuthorizationDenied(ActionAuthorizationFailure failure) {
    _metrics?.recordLocalAuthorizationDenied();
  }
}
