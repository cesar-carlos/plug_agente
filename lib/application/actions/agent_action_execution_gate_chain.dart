import 'package:plug_agente/application/actions/agent_action_dangerous_command_policy_enforcer.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_execution_validator.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_request_validator.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/actions/elevated_agent_action_execution_service.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentActionAuthorizationDeniedRecorder = void Function(ActionAuthorizationFailure failure);

class AgentActionGatedExecutionContext {
  const AgentActionGatedExecutionContext({
    required this.definition,
    required this.runner,
  });

  final AgentActionDefinition definition;
  final AgentActionLocalRunner runner;
}

/// Shared pre-execution gate pipeline for local runs and remote dry-run validation.
class AgentActionExecutionGateChain {
  AgentActionExecutionGateChain({
    required IAgentActionRepository repository,
    required AgentActionLocalRunnerRegistry runnerRegistry,
    AgentActionRuntimeRequestValidator? runtimeRequestValidator,
    AgentActionRuntimeExecutionValidator? runtimeExecutionValidator,
    AgentActionRuntimeStateGuard? runtimeStateGuard,
    FeatureFlags? featureFlags,
    AgentOperationalProfileResolver? operationalProfileResolver,
    AgentActionSecretPlaceholderResolver? secretPlaceholderResolver,
    AgentActionDangerousCommandPolicyEnforcer? dangerousCommandPolicyEnforcer,
    ElevatedActionRunnerReadinessService? elevatedRunnerReadiness,
    ElevatedAgentActionExecutionService? elevatedExecutionService,
    AgentActionDefinitionSnapshotter? definitionSnapshotter,
    AgentActionSecretReferenceFingerprinter? secretReferenceFingerprinter,
  }) : _repository = repository,
       _runnerRegistry = runnerRegistry,
       _runtimeRequestValidator = runtimeRequestValidator ?? const AgentActionRuntimeRequestValidator(),
       _runtimeExecutionValidator = runtimeExecutionValidator ?? const AgentActionRuntimeExecutionValidator(),
       _runtimeStateGuard = runtimeStateGuard,
       _featureFlags = featureFlags,
       _operationalProfileResolver = operationalProfileResolver,
       _secretPlaceholderResolver = secretPlaceholderResolver ?? const AgentActionSecretPlaceholderResolver(),
       _dangerousCommandPolicyEnforcer = dangerousCommandPolicyEnforcer,
       _elevatedRunnerReadiness = elevatedRunnerReadiness,
       _elevatedExecutionService = elevatedExecutionService,
       _definitionSnapshotter = definitionSnapshotter,
       _secretReferenceFingerprinter = secretReferenceFingerprinter;

  final IAgentActionRepository _repository;
  final AgentActionLocalRunnerRegistry _runnerRegistry;
  final AgentActionRuntimeRequestValidator _runtimeRequestValidator;
  final AgentActionRuntimeExecutionValidator _runtimeExecutionValidator;
  final AgentActionRuntimeStateGuard? _runtimeStateGuard;
  final FeatureFlags? _featureFlags;
  final AgentOperationalProfileResolver? _operationalProfileResolver;
  final AgentActionSecretPlaceholderResolver _secretPlaceholderResolver;
  final AgentActionDangerousCommandPolicyEnforcer? _dangerousCommandPolicyEnforcer;
  final ElevatedActionRunnerReadinessService? _elevatedRunnerReadiness;
  final ElevatedAgentActionExecutionService? _elevatedExecutionService;
  final AgentActionDefinitionSnapshotter? _definitionSnapshotter;
  final AgentActionSecretReferenceFingerprinter? _secretReferenceFingerprinter;

  Future<Result<AgentActionGatedExecutionContext>> evaluate({
    required AgentActionExecutionRequest request,
    AgentActionAuthorizationDeniedRecorder? onAuthorizationDenied,
  }) async {
    final requestValidationResult = _runtimeRequestValidator.validate(request);
    if (requestValidationResult.isError()) {
      return Failure(requestValidationResult.exceptionOrNull()!);
    }

    final featureGateResult = _ensureFeatureGateAllows(request);
    if (featureGateResult.isError()) {
      final failure = featureGateResult.exceptionOrNull()!;
      _recordAuthorizationDenied(onAuthorizationDenied, failure);
      return Failure(failure);
    }

    final definitionResult = await _repository.getDefinition(request.actionId.trim());
    if (definitionResult.isError()) {
      return Failure(definitionResult.exceptionOrNull()!);
    }
    final definition = definitionResult.getOrThrow();
    if (!definition.canRun) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action is not active and cannot be executed.',
          context: {
            'action_id': definition.id,
            'state': definition.state.name,
            'reason': AgentActionGateConstants.actionNotActiveReason,
            'user_message': 'The action is not active. Validate or activate the action before running.',
          },
        ),
      );
    }

    final remoteRiskResult = await _ensureRemoteRiskFingerprintCurrent(definition: definition);
    if (remoteRiskResult.isError()) {
      final failure = remoteRiskResult.exceptionOrNull()!;
      _recordAuthorizationDenied(onAuthorizationDenied, failure);
      return Failure(failure);
    }

    final remoteGateResult = _ensureRemoteExecutionAllowed(
      definition: definition,
      request: request,
    );
    if (remoteGateResult.isError()) {
      final failure = remoteGateResult.exceptionOrNull()!;
      _recordAuthorizationDenied(onAuthorizationDenied, failure);
      return Failure(failure);
    }

    final runtimeGateResult = _ensureRuntimeStateAllows(
      definition: definition,
      request: request,
    );
    if (runtimeGateResult.isError()) {
      final failure = runtimeGateResult.exceptionOrNull()!;
      _recordAuthorizationDenied(onAuthorizationDenied, failure);
      return Failure(failure);
    }

    final environmentGateResult = _ensureEnvironmentAllows(definition: definition);
    if (environmentGateResult.isError()) {
      final failure = environmentGateResult.exceptionOrNull()!;
      _recordAuthorizationDenied(onAuthorizationDenied, failure);
      return Failure(failure);
    }

    final runtimePolicyResult = _runtimeExecutionValidator.validateForExecution(
      definition: definition,
      request: request,
    );
    if (runtimePolicyResult.isError()) {
      return Failure(runtimePolicyResult.exceptionOrNull()!);
    }

    final secretGateResult = await _secretPlaceholderResolver.ensureResolvable(definition);
    if (secretGateResult.isError()) {
      return Failure(secretGateResult.exceptionOrNull()!);
    }

    final dangerousCommandResult = _dangerousCommandPolicyEnforcer?.enforce(
      definition: definition,
      request: request,
    );
    if (dangerousCommandResult != null && dangerousCommandResult.isError()) {
      return Failure(dangerousCommandResult.exceptionOrNull()!);
    }

    final elevatedGateResult = _ensureElevatedExecutionAllowed(definition: definition);
    if (elevatedGateResult.isError()) {
      final failure = elevatedGateResult.exceptionOrNull()!;
      _recordAuthorizationDenied(onAuthorizationDenied, failure);
      return Failure(failure);
    }

    if (definition.policies.elevated.runElevated) {
      final elevatedTypeResult = _elevatedExecutionService?.ensureActionTypeSupported(definition);
      if (elevatedTypeResult != null && elevatedTypeResult.isError()) {
        final failure = elevatedTypeResult.exceptionOrNull()!;
        _recordAuthorizationDenied(onAuthorizationDenied, failure);
        return Failure(failure);
      }
    }

    final runnerResult = _runnerRegistry.resolve(definition.type);
    if (runnerResult.isError()) {
      return Failure(runnerResult.exceptionOrNull()!);
    }

    return Success(
      AgentActionGatedExecutionContext(
        definition: definition,
        runner: runnerResult.getOrThrow(),
      ),
    );
  }

  Future<Result<AgentActionPreparedExecution>> evaluateAdapterPrepare({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    required AgentActionAdapterRegistry adapterRegistry,
  }) async {
    final adapterResult = adapterRegistry.resolve(definition.type);
    if (adapterResult.isError()) {
      return Failure(adapterResult.exceptionOrNull()!);
    }

    return adapterResult.getOrThrow().prepareExecution(
      definition: definition,
      request: request,
    );
  }

  void _recordAuthorizationDenied(
    AgentActionAuthorizationDeniedRecorder? onAuthorizationDenied,
    Object failure,
  ) {
    if (failure is ActionAuthorizationFailure) {
      onAuthorizationDenied?.call(failure);
    }
  }

  Result<void> _ensureFeatureGateAllows(
    AgentActionExecutionRequest request,
  ) {
    final flags = _featureFlags;
    if (flags == null) {
      return const Success(unit);
    }

    if (!flags.enableAgentActions) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Agent actions are disabled by feature flag.',
          code: AgentActionFailureCode.featureDisabled,
          context: const {
            'reason': AgentActionGateConstants.featureDisabledReason,
            'user_message': 'Agent actions are disabled in this environment.',
          },
        ),
      );
    }

    if (flags.enableAgentActionsMaintenanceMode) {
      final blocksLocal =
          request.source == AgentActionRequestSource.localUi && flags.enableAgentActionsMaintenanceStrictMode;
      if (request.source != AgentActionRequestSource.localUi || blocksLocal) {
        return Failure(
          ActionAuthorizationFailure.withContext(
            message: blocksLocal
                ? 'Agent actions maintenance mode blocks all executions including manual runs.'
                : 'Agent actions maintenance mode blocks non-manual executions.',
            code: AgentActionFailureCode.maintenanceMode,
            context: {
              'reason': AgentActionGateConstants.maintenanceModeReason,
              'source': request.source.name,
              'maintenance_strict_mode': flags.enableAgentActionsMaintenanceStrictMode,
              'user_message': blocksLocal
                  ? 'Todas as execucoes estao bloqueadas pelo modo de manutencao, incluindo execucao manual.'
                  : 'As execucoes remotas e agendadas estao bloqueadas pelo modo de manutencao.',
            },
          ),
        );
      }
    }

    return const Success(unit);
  }

  Result<void> _ensureElevatedExecutionAllowed({
    required AgentActionDefinition definition,
  }) {
    if (!definition.policies.elevated.runElevated) {
      return const Success(unit);
    }

    final flags = _featureFlags;
    if (flags != null && !flags.enableElevatedAgentActions) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Elevated agent action execution is disabled by feature flag.',
          code: AgentActionFailureCode.elevatedDisabled,
          context: {
            'action_id': definition.id,
            'reason': AgentActionGateConstants.elevatedDisabledReason,
            'user_message':
                'A execucao elevada esta desativada neste agente. Use execucao local padrao ou habilite a feature flag de acoes elevadas.',
          },
        ),
      );
    }

    final readiness = _elevatedRunnerReadiness;
    if (readiness == null) {
      return const Success(unit);
    }

    if (readiness.isDegraded) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Elevated agent action runner is degraded.',
          code: AgentActionFailureCode.elevatedRunnerDegraded,
          context: {
            'action_id': definition.id,
            'reason': AgentActionGateConstants.elevatedRunnerDegradedReason,
            if (readiness.degradedReason != null) 'degraded_reason': readiness.degradedReason,
            'user_message':
                'O executor elevado esta indisponivel. Reinstale ou reinicie o helper elevado antes de executar esta acao.',
          },
        ),
      );
    }

    if (!readiness.isConfigured) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Elevated agent action runner is not configured on this host.',
          code: AgentActionFailureCode.elevatedNotConfigured,
          context: {
            'action_id': definition.id,
            'reason': AgentActionGateConstants.elevatedNotConfiguredReason,
            'user_message':
                'A execucao elevada requer o helper instalado neste agente. Conclua a preparacao do runner elevado na UI ou pelo instalador.',
          },
        ),
      );
    }

    return const Success(unit);
  }

  Future<Result<void>> _ensureRemoteRiskFingerprintCurrent({
    required AgentActionDefinition definition,
  }) async {
    final remote = definition.policies.remote;
    if (!remote.isEnabled || remote.approvedAt == null) {
      return const Success(unit);
    }

    final approvedFingerprint = remote.riskFingerprint;
    if (approvedFingerprint == null || approvedFingerprint.trim().isEmpty) {
      return const Success(unit);
    }

    final snapshotter = _definitionSnapshotter;
    final fingerprinter = _secretReferenceFingerprinter;
    if (snapshotter == null || fingerprinter == null) {
      return const Success(unit);
    }

    final secretFingerprints = await fingerprinter.fingerprintsFor(definition);
    final currentFingerprint = snapshotter.riskFingerprint(
      definition,
      secretReferenceFingerprints: secretFingerprints.isEmpty ? null : secretFingerprints,
    );
    if (currentFingerprint == approvedFingerprint) {
      return const Success(unit);
    }

    return Failure(
      ActionAuthorizationFailure.withContext(
        message: 'Remote action approval is stale after a risk-bearing change.',
        code: AgentActionFailureCode.remoteNotApproved,
        context: {
          'action_id': definition.id,
          'remote_requires_reapproval': true,
          'reason': AgentActionGateConstants.remoteRiskFingerprintStaleReason,
          'user_message':
              'A aprovacao remota desta acao nao reflete mais a configuracao atual (por exemplo, segredo rotacionado). Reaprove na pagina Acoes antes de executar pelo Hub.',
        },
      ),
    );
  }

  Result<void> _ensureRemoteExecutionAllowed({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) {
    if (request.source != AgentActionRequestSource.remoteHub) {
      return const Success(unit);
    }

    if (_featureFlags != null && !_featureFlags.enableRemoteAgentActions) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Remote agent actions are disabled by feature flag.',
          code: AgentActionFailureCode.remoteFeatureDisabled,
          context: {
            'action_id': definition.id,
            'source': request.source.name,
            'reason': AgentActionGateConstants.remoteFeatureDisabledReason,
            'user_message': 'Remote action executions are disabled in this environment.',
          },
        ),
      );
    }

    if (!definition.policies.remote.canRunSavedAction) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Action is not approved for remote execution.',
          code: AgentActionFailureCode.remoteNotApproved,
          context: {
            'action_id': definition.id,
            'source': request.source.name,
            'remote_enabled': definition.policies.remote.isEnabled,
            'remote_approved': definition.policies.remote.approvedAt != null,
            'remote_requires_reapproval': definition.policies.remote.requiresReapproval,
            'reason': AgentActionGateConstants.remoteActionNotApprovedReason,
            'user_message': 'The action is not approved for remote execution.',
          },
        ),
      );
    }

    if (definition.policies.remote.allowAdHoc) {
      if (_featureFlags != null && !_featureFlags.enableRemoteAdHocAgentActions) {
        return Failure(
          ActionAuthorizationFailure.withContext(
            message: 'Remote ad-hoc agent actions are disabled by feature flag.',
            code: AgentActionFailureCode.remoteAdHocDisabled,
            context: {
              'action_id': definition.id,
              'source': request.source.name,
              'reason': AgentActionGateConstants.remoteAdHocDisabledReason,
              'user_message':
                  'Comandos remotos ad-hoc estao desativados neste agente. Habilite a feature flag de ad-hoc remoto.',
            },
          ),
        );
      }
    }

    final idempotencyKey = _canonicalOptionalRequestString(request.idempotencyKey);
    if (idempotencyKey == null) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Remote agent action execution requires an idempotency key.',
          code: AgentActionFailureCode.remoteIdempotencyRequired,
          context: {
            'action_id': definition.id,
            'source': request.source.name,
            'field': 'idempotencyKey',
            'reason': AgentActionRpcConstants.remoteIdempotencyRequiredRpcReason,
            'user_message': 'Remote execution requires an idempotency key.',
          },
        ),
      );
    }

    if (_canonicalOptionalRequestString(request.contextPath) != null) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Remote agent action execution does not accept inline context in MVP.',
          code: AgentActionFailureCode.remoteContextNotSupported,
          context: {
            'action_id': definition.id,
            'source': request.source.name,
            'field': 'contextPath',
            'reason': AgentActionRpcConstants.remoteContextNotSupportedRpcReason,
            'user_message': 'Inline context is not supported in remote executions in this version.',
          },
        ),
      );
    }

    if (request.runtimeParameters.isNotEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Remote agent action execution does not accept runtime parameters in MVP.',
          code: AgentActionFailureCode.remoteContextNotSupported,
          context: {
            'action_id': definition.id,
            'source': request.source.name,
            'field': 'runtimeParameters',
            'reason': AgentActionRpcConstants.remoteContextNotSupportedRpcReason,
            'user_message': 'Runtime parameters are not supported in remote executions in this version.',
          },
        ),
      );
    }

    return const Success(unit);
  }

  Result<void> _ensureEnvironmentAllows({
    required AgentActionDefinition definition,
  }) {
    final allowedProfiles = definition.policies.environment.allowedProfiles;
    if (allowedProfiles.isEmpty) {
      return const Success(unit);
    }

    final profile = _operationalProfileResolver?.currentProfile;
    if (definition.policies.environment.allowsProfile(profile)) {
      return const Success(unit);
    }

    return Failure(
      ActionAuthorizationFailure.withContext(
        message: 'Action is not allowed in the current agent operational profile.',
        code: AgentActionFailureCode.environmentProfileDenied,
        context: {
          'action_id': definition.id,
          'allowed_profiles': allowedProfiles.toList(growable: false),
          'current_profile': profile,
          'reason': AgentActionGateConstants.environmentProfileDeniedReason,
          'user_message': 'The action is not authorized for the agent current operational profile.',
        },
      ),
    );
  }

  Result<void> _ensureRuntimeStateAllows({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) {
    final guard = _runtimeStateGuard;
    if (guard == null) {
      return const Success(unit);
    }

    return guard.ensureCanAcceptExecution(
      request: request,
      actionType: definition.type,
    );
  }

  String? _canonicalOptionalRequestString(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
