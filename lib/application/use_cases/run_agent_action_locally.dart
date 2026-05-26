import 'dart:async';
import 'dart:convert';

import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/application/actions/agent_action_failure_process_metadata.dart';
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
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class RunAgentActionLocally {
  RunAgentActionLocally(
    this._repository,
    this._runnerRegistry,
    this._uuid, {
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
    DateTime Function()? now,
  }) : _executionQueue = executionQueue ?? ActionExecutionQueue(),
       _runtimeRequestValidator = runtimeRequestValidator ?? const AgentActionRuntimeRequestValidator(),
       _runtimeExecutionValidator = runtimeExecutionValidator ?? const AgentActionRuntimeExecutionValidator(),
       _runtimeStateGuard = runtimeStateGuard,
       _featureFlags = featureFlags,
       _saveExecution = saveExecution ?? SaveAgentActionExecution(_repository),
       _runtimeIdentity = runtimeIdentity,
       _metrics = metrics,
       _operationalProfileResolver = operationalProfileResolver,
       _notifyExecution = notifyExecution,
       _secretPlaceholderResolver = secretPlaceholderResolver ?? const AgentActionSecretPlaceholderResolver(),
       _adapterRegistry = adapterRegistry,
       _elevatedRunnerReadiness = elevatedRunnerReadiness,
       _elevatedExecutionService = elevatedExecutionService,
       _remoteLifecycleAudit = remoteLifecycleAudit,
       _definitionSnapshotter = definitionSnapshotter,
       _secretReferenceFingerprinter = secretReferenceFingerprinter,
       _now = now ?? DateTime.now;

  final IAgentActionRepository _repository;
  final AgentActionLocalRunnerRegistry _runnerRegistry;
  final Uuid _uuid;
  final ActionExecutionQueue _executionQueue;
  final AgentActionRuntimeRequestValidator _runtimeRequestValidator;
  final AgentActionRuntimeExecutionValidator _runtimeExecutionValidator;
  final AgentActionRuntimeStateGuard? _runtimeStateGuard;
  final FeatureFlags? _featureFlags;
  final SaveAgentActionExecution _saveExecution;
  final AgentRuntimeIdentity? _runtimeIdentity;
  final AgentActionExecutionMetricsCollector? _metrics;
  final AgentOperationalProfileResolver? _operationalProfileResolver;
  final NotifyAgentActionExecutionIfConfigured? _notifyExecution;
  final AgentActionSecretPlaceholderResolver _secretPlaceholderResolver;
  final AgentActionAdapterRegistry? _adapterRegistry;
  final ElevatedActionRunnerReadinessService? _elevatedRunnerReadiness;
  final ElevatedAgentActionExecutionService? _elevatedExecutionService;
  final AgentActionRemoteLifecycleAuditRecorder? _remoteLifecycleAudit;
  final AgentActionDefinitionSnapshotter? _definitionSnapshotter;
  final AgentActionSecretReferenceFingerprinter? _secretReferenceFingerprinter;
  final DateTime Function() _now;
  final Map<String, Future<Result<AgentActionExecution>>> _idempotentExecutions =
      <String, Future<Result<AgentActionExecution>>>{};

  Future<Result<AgentActionExecution>> call(
    AgentActionExecutionRequest request,
  ) async {
    final requestValidationResult = _runtimeRequestValidator.validate(request);
    if (requestValidationResult.isError()) {
      return Failure(requestValidationResult.exceptionOrNull()!);
    }

    final featureGateResult = _ensureFeatureGateAllows(request);
    if (featureGateResult.isError()) {
      final failure = featureGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
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
      _recordLocalAuthorizationDeniedIfApplicable(failure);
      return Failure(failure);
    }

    final remoteGateResult = _ensureRemoteExecutionAllowed(
      definition: definition,
      request: request,
    );
    if (remoteGateResult.isError()) {
      final failure = remoteGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
      return Failure(failure);
    }

    final runtimeGateResult = _ensureRuntimeStateAllows(
      definition: definition,
      request: request,
    );
    if (runtimeGateResult.isError()) {
      final failure = runtimeGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
      return Failure(failure);
    }

    final environmentGateResult = _ensureEnvironmentAllows(definition: definition);
    if (environmentGateResult.isError()) {
      final failure = environmentGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
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

    final elevatedGateResult = _ensureElevatedExecutionAllowed(definition: definition);
    if (elevatedGateResult.isError()) {
      final failure = elevatedGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
      return Failure(failure);
    }

    if (definition.policies.elevated.runElevated) {
      final elevatedTypeResult = _elevatedExecutionService?.ensureActionTypeSupported(definition);
      if (elevatedTypeResult != null && elevatedTypeResult.isError()) {
        final failure = elevatedTypeResult.exceptionOrNull()!;
        _recordLocalAuthorizationDeniedIfApplicable(failure);
        return Failure(failure);
      }
    }

    final runnerResult = _runnerRegistry.resolve(definition.type);
    if (runnerResult.isError()) {
      return Failure(runnerResult.exceptionOrNull()!);
    }

    final idempotencyKey = _idempotencyKeyFor(request);
    if (idempotencyKey != null) {
      final existing = _idempotentExecutions[idempotencyKey];
      if (existing != null) {
        if (request.returnWhenQueued) {
          final persistedExecutionResult = await _findPersistedIdempotentExecution(
            actionId: definition.id,
            idempotencyKey: _canonicalOptionalRequestString(request.idempotencyKey)!,
          );
          if (persistedExecutionResult.isError()) {
            return Failure(persistedExecutionResult.exceptionOrNull()!);
          }
          final persistedExecutions = persistedExecutionResult.getOrThrow();
          if (persistedExecutions.isNotEmpty) {
            return Success(persistedExecutions.first);
          }
        }
        return existing;
      }
      final persistedExecutionResult = await _findPersistedIdempotentExecution(
        actionId: definition.id,
        idempotencyKey: _canonicalOptionalRequestString(request.idempotencyKey)!,
      );
      if (persistedExecutionResult.isError()) {
        return Failure(persistedExecutionResult.exceptionOrNull()!);
      }
      final persistedExecutions = persistedExecutionResult.getOrThrow();
      if (persistedExecutions.isNotEmpty) {
        return Success(persistedExecutions.first);
      }
    }

    final startResult = await _startExecution(
      definition: definition,
      request: request,
      runner: runnerResult.getOrThrow(),
    );
    if (startResult.isError()) {
      return Failure(startResult.exceptionOrNull()!);
    }
    final startedExecution = startResult.getOrThrow();
    if (idempotencyKey != null) {
      _idempotentExecutions[idempotencyKey] = startedExecution.completion;
      // Remove after completion: post-execution retries are handled by DB-level
      // idempotency (listExecutions with idempotencyKey filter). Keeping
      // completed futures indefinitely leaks memory on long-running agents.
      unawaited(
        startedExecution.completion.whenComplete(
          () => _idempotentExecutions.remove(idempotencyKey),
        ),
      );
    }

    if (request.returnWhenQueued) {
      unawaited(startedExecution.completion);
      return Success(startedExecution.queuedExecution);
    }

    return startedExecution.completion;
  }

  /// Validates that a remote run would pass the same gates as [call] up to queue admission,
  /// without persisting an execution or starting a process.
  Future<Result<AgentActionValidateRunSummary>> validateRemoteRun(
    AgentActionExecutionRequest request,
  ) async {
    final requestValidationResult = _runtimeRequestValidator.validate(request);
    if (requestValidationResult.isError()) {
      return Failure(requestValidationResult.exceptionOrNull()!);
    }

    final featureGateResult = _ensureFeatureGateAllows(request);
    if (featureGateResult.isError()) {
      final failure = featureGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
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
      _recordLocalAuthorizationDeniedIfApplicable(failure);
      return Failure(failure);
    }

    final remoteGateResult = _ensureRemoteExecutionAllowed(
      definition: definition,
      request: request,
    );
    if (remoteGateResult.isError()) {
      final failure = remoteGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
      return Failure(failure);
    }

    final runtimeGateResult = _ensureRuntimeStateAllows(
      definition: definition,
      request: request,
    );
    if (runtimeGateResult.isError()) {
      final failure = runtimeGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
      return Failure(failure);
    }

    final environmentGateResult = _ensureEnvironmentAllows(definition: definition);
    if (environmentGateResult.isError()) {
      final failure = environmentGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
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

    final elevatedGateResult = _ensureElevatedExecutionAllowed(definition: definition);
    if (elevatedGateResult.isError()) {
      final failure = elevatedGateResult.exceptionOrNull()!;
      _recordLocalAuthorizationDeniedIfApplicable(failure);
      return Failure(failure);
    }

    if (definition.policies.elevated.runElevated) {
      final elevatedTypeResult = _elevatedExecutionService?.ensureActionTypeSupported(definition);
      if (elevatedTypeResult != null && elevatedTypeResult.isError()) {
        final failure = elevatedTypeResult.exceptionOrNull()!;
        _recordLocalAuthorizationDeniedIfApplicable(failure);
        return Failure(failure);
      }
    }

    final runnerResult = _runnerRegistry.resolve(definition.type);
    if (runnerResult.isError()) {
      return Failure(runnerResult.exceptionOrNull()!);
    }

    final idempotencyKey = _idempotencyKeyFor(request);
    if (idempotencyKey != null) {
      if (_idempotentExecutions.containsKey(idempotencyKey)) {
        return Success(
          AgentActionValidateRunSummary(
            actionId: definition.id,
            actionType: definition.type,
            definitionSnapshotHash: definition.definitionSnapshotHash,
            wouldReplayExistingExecution: true,
          ),
        );
      }
      final persistedExecutionResult = await _findPersistedIdempotentExecution(
        actionId: definition.id,
        idempotencyKey: _canonicalOptionalRequestString(request.idempotencyKey)!,
      );
      if (persistedExecutionResult.isError()) {
        return Failure(persistedExecutionResult.exceptionOrNull()!);
      }
      final persistedExecutions = persistedExecutionResult.getOrThrow();
      if (persistedExecutions.isNotEmpty) {
        return Success(
          AgentActionValidateRunSummary(
            actionId: definition.id,
            actionType: definition.type,
            definitionSnapshotHash: definition.definitionSnapshotHash,
            wouldReplayExistingExecution: true,
            existingExecutionId: persistedExecutions.first.id,
          ),
        );
      }
    }

    final queueAdmission = _executionQueue.validateRemoteAdmission(
      actionId: definition.id,
      policies: definition.policies,
    );
    if (queueAdmission.isError()) {
      return Failure(queueAdmission.exceptionOrNull()!);
    }

    final adapterRegistry = _adapterRegistry;
    if (adapterRegistry != null) {
      final adapterResult = adapterRegistry.resolve(definition.type);
      if (adapterResult.isError()) {
        return Failure(adapterResult.exceptionOrNull()!);
      }
      final prepareResult = await adapterResult.getOrThrow().prepareExecution(
        definition: definition,
        request: request,
      );
      if (prepareResult.isError()) {
        return Failure(prepareResult.exceptionOrNull()!);
      }
    }

    return Success(
      AgentActionValidateRunSummary(
        actionId: definition.id,
        actionType: definition.type,
        definitionSnapshotHash: definition.definitionSnapshotHash,
      ),
    );
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

  Future<Result<List<AgentActionExecution>>> _findPersistedIdempotentExecution({
    required String actionId,
    required String idempotencyKey,
  }) async {
    final result = await _repository.listExecutions(
      actionId: actionId,
      idempotencyKey: idempotencyKey,
      limit: 1,
    );
    if (result.isError()) {
      return Failure(result.exceptionOrNull()!);
    }

    return result;
  }

  Future<Result<_StartedAgentActionExecution>> _startExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    required AgentActionLocalRunner runner,
  }) async {
    final requestedAt = _now();
    final persistedIdempotencyKey = _canonicalOptionalRequestString(request.idempotencyKey);
    final persistedRequestedBy = _canonicalOptionalRequestString(request.requestedBy);
    final persistedTraceId = _canonicalOptionalRequestString(request.traceId);
    final persistedTriggerId = _canonicalOptionalRequestString(request.triggerId);
    final identity = _runtimeIdentity;
    final queuedExecution = AgentActionExecution(
      id: _uuid.v4(),
      actionId: definition.id,
      actionType: definition.type,
      status: AgentActionExecutionStatus.queued,
      requestedAt: requestedAt,
      source: request.source,
      idempotencyKey: persistedIdempotencyKey,
      requestedBy: persistedRequestedBy,
      traceId: persistedTraceId,
      runtimeInstanceId: identity?.runtimeInstanceId,
      runtimeSessionId: identity?.runtimeSessionId,
      triggerId: persistedTriggerId,
      triggerType: request.triggerType,
      scheduledAt: request.scheduledAt,
      triggeredAt: request.triggeredAt,
      queueStartedAt: requestedAt,
      definitionSnapshotHash: definition.definitionSnapshotHash,
    );
    final initialSaveResult = await _saveExecution(queuedExecution);
    if (initialSaveResult.isError()) {
      return Failure(initialSaveResult.exceptionOrNull()!);
    }

    await _remoteLifecycleAudit?.recordEnqueued(queuedExecution);

    final completion = _observeQueueCompletion(
      queuedExecution: queuedExecution,
      queuedResult: _executionQueue.enqueue(
        AgentActionQueueRequest<AgentActionExecution>(
          actionId: definition.id,
          executionId: queuedExecution.id,
          idempotencyKey: persistedIdempotencyKey,
          policies: definition.policies,
          task: () => _runPersistedExecution(
            queuedExecution: queuedExecution,
            definition: definition,
            request: request,
            runner: runner,
          ),
        ),
      ),
    );

    return Success(
      _StartedAgentActionExecution(
        queuedExecution: queuedExecution,
        completion: completion,
      ),
    );
  }

  Future<Result<AgentActionExecution>> _observeQueueCompletion({
    required AgentActionExecution queuedExecution,
    required Future<Result<AgentActionExecution>> queuedResult,
  }) async {
    final result = await queuedResult;
    if (result.isSuccess()) {
      return result;
    }

    final actionFailure = _toActionFailure(result.exceptionOrNull()!);
    final rejectedExecution = queuedExecution.copyWith(
      status: _queuedFailureStatus(actionFailure),
      finishedAt: _now(),
      redactionApplied: true,
      failureCode: actionFailure.code,
      failurePhase: _failurePhaseForFailure(actionFailure),
      failureMessage: actionFailure.message,
    );
    final rejectedSaveResult = await _saveExecution(rejectedExecution);
    if (rejectedSaveResult.isError()) {
      return Failure(rejectedSaveResult.exceptionOrNull()!);
    }

    _recordTerminalExecutionMetrics(rejectedExecution);
    await _remoteLifecycleAudit?.recordFinished(
      execution: rejectedExecution,
      rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
    );
    return Failure(actionFailure);
  }

  AgentActionExecutionStatus _queuedFailureStatus(ActionFailure actionFailure) {
    return switch (actionFailure.code) {
      AgentActionFailureCode.queueCancelled => AgentActionExecutionStatus.cancelled,
      AgentActionFailureCode.queueIgnored => AgentActionExecutionStatus.skipped,
      _ => AgentActionExecutionStatus.failed,
    };
  }

  String? _idempotencyKeyFor(AgentActionExecutionRequest request) {
    final idempotencyKey = _canonicalOptionalRequestString(request.idempotencyKey);
    if (idempotencyKey == null) {
      return null;
    }

    return '${request.actionId.trim()}:$idempotencyKey';
  }

  String? _canonicalOptionalRequestString(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<Result<AgentActionProcessResult>> _runElevatedExecution({
    required String executionId,
    required AgentActionDefinition definition,
  }) async {
    final service = _elevatedExecutionService;
    if (service == null) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Elevated execution service is not configured.',
          code: AgentActionFailureCode.elevatedNotConfigured,
          context: {
            'execution_id': executionId,
            'phase': AgentActionProcessConstants.elevatedSubmitPhase,
            'reason': AgentActionGateConstants.elevatedNotConfiguredReason,
            'user_message': 'The elevated execution service is not available on this agent.',
          },
        ),
      );
    }

    return service.run(
      executionId: executionId,
      definition: definition,
    );
  }

  Future<Result<AgentActionExecution>> _runPersistedExecution({
    required AgentActionExecution queuedExecution,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    required AgentActionLocalRunner runner,
  }) async {
    var runningExecution = queuedExecution.copyWith(
      status: AgentActionExecutionStatus.running,
      processStartedAt: _now(),
    );
    final runningSaveResult = await _saveExecution(runningExecution);
    if (runningSaveResult.isError()) {
      return Failure(runningSaveResult.exceptionOrNull()!);
    }

    await _remoteLifecycleAudit?.recordStarted(runningExecution);

    final retryPolicy = definition.policies.retry;
    final maxAttempts = retryPolicy.effectiveMaxAttempts(
      request,
      runElevated: definition.policies.elevated.runElevated,
    );
    var terminalExecution = runningExecution;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        if (retryPolicy.delayBetweenAttempts > Duration.zero) {
          await Future<void>.delayed(retryPolicy.delayBetweenAttempts);
        }
        // Re-validate the subsystem guard before each retry attempt. The guard
        // may have transitioned to draining or maintenance while the previous
        // attempt was running (e.g. app-close or feature rollback).
        final guardCheck = _ensureRuntimeStateAllows(
          definition: definition,
          request: request,
        );
        if (guardCheck.isError()) {
          return Failure(guardCheck.exceptionOrNull()!);
        }
        runningExecution = runningExecution.copyWith(
          status: AgentActionExecutionStatus.running,
          processStartedAt: _now(),
        );
        final retryRunningSave = await _saveExecution(runningExecution);
        if (retryRunningSave.isError()) {
          return Failure(retryRunningSave.exceptionOrNull()!);
        }
      }

      final resolvedDefinitionResult = await _secretPlaceholderResolver.resolveForExecution(
        definition,
      );
      if (resolvedDefinitionResult.isError()) {
        return Failure(resolvedDefinitionResult.exceptionOrNull()!);
      }

      final resolvedDefinition = resolvedDefinitionResult.getOrThrow();
      final runResult = resolvedDefinition.policies.elevated.runElevated
          ? await _runElevatedExecution(
              executionId: runningExecution.id,
              definition: resolvedDefinition,
            )
          : await runner.run(
              executionId: runningExecution.id,
              definition: resolvedDefinition,
              request: request,
            );
      terminalExecution = runResult.fold(
        (output) => _executionFromOutput(runningExecution, output),
        (failure) => _failedExecutionFromFailure(
          runningExecution,
          failure,
        ),
      );

      if (terminalExecution.status.isSuccess ||
          !retryPolicy.isRetriableStatus(terminalExecution.status) ||
          attempt >= maxAttempts) {
        break;
      }
    }

    return _finalizeTerminalExecution(
      definition: definition,
      terminalExecution: terminalExecution,
    );
  }

  Future<Result<AgentActionExecution>> _finalizeTerminalExecution({
    required AgentActionDefinition definition,
    required AgentActionExecution terminalExecution,
  }) async {
    final terminalSaveResult = await _saveExecution(terminalExecution);
    if (terminalSaveResult.isError()) {
      return Failure(terminalSaveResult.exceptionOrNull()!);
    }

    _recordTerminalExecutionMetrics(terminalExecution);
    await _remoteLifecycleAudit?.recordFinished(
      execution: terminalExecution,
      rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
    );
    final notify = _notifyExecution;
    if (notify != null) {
      await notify(
        definition: definition,
        execution: terminalExecution,
      );
    }

    return terminalSaveResult;
  }

  void _recordTerminalExecutionMetrics(AgentActionExecution execution) {
    final metrics = _metrics;
    if (metrics == null || !execution.isTerminal) {
      return;
    }

    metrics.recordTerminalOutcome(execution.status);
    metrics.recordCapturedOutputPersisted(
      stdoutCaptured: execution.stdoutText != null,
      stderrCaptured: execution.stderrText != null,
      stdoutTruncated: execution.stdoutTruncated,
      stderrTruncated: execution.stderrTruncated,
      stdoutUtf8Bytes: _utf8ByteLength(execution.stdoutText),
      stderrUtf8Bytes: _utf8ByteLength(execution.stderrText),
    );
    final finishedAt = execution.finishedAt;
    if (finishedAt == null) {
      return;
    }

    final startedAt = execution.processStartedAt ?? execution.queueStartedAt ?? execution.requestedAt;
    metrics.recordExecutionDuration(finishedAt.difference(startedAt));
  }

  AgentActionExecution _failedExecutionFromFailure(
    AgentActionExecution runningExecution,
    Exception failure,
  ) {
    final actionFailure = _toActionFailure(failure);
    final processMetadata = AgentActionFailureProcessMetadata.fromFailureContext(
      actionFailure.context,
    );
    return runningExecution.copyWith(
      status: AgentActionExecutionStatus.failed,
      finishedAt: _now(),
      redactionApplied: true,
      failureCode: actionFailure.code,
      failurePhase: _failurePhaseForFailure(actionFailure),
      failureMessage: actionFailure.message,
      processExecutable: processMetadata.processExecutable ?? runningExecution.processExecutable,
      processArgumentCount: processMetadata.processArgumentCount ?? runningExecution.processArgumentCount,
      processCommandPreview: processMetadata.processCommandPreview ?? runningExecution.processCommandPreview,
    );
  }

  ActionFailure _toActionFailure(Exception failure) {
    return failure is ActionFailure ? failure : ActionRuntimeFailure(failure.toString());
  }

  AgentActionExecution _executionFromOutput(
    AgentActionExecution initialExecution,
    AgentActionProcessResult output,
  ) {
    return initialExecution.copyWith(
      status: output.status,
      processStartedAt: output.processStartedAt,
      finishedAt: output.finishedAt,
      timeoutAt: output.timedOut ? output.finishedAt : null,
      pid: output.pid,
      exitCode: output.exitCode,
      processExecutable: output.processExecutable,
      processArgumentCount: output.processArgumentCount,
      processCommandPreview: output.processCommandPreview,
      stdoutText: output.stdout.isCaptured ? output.stdout.text : null,
      stderrText: output.stderr.isCaptured ? output.stderr.text : null,
      stdoutTruncated: output.stdout.isTruncated,
      stderrTruncated: output.stderr.isTruncated,
      contextHash: output.contextHash,
      redactionApplied: output.redactionApplied,
      failureCode: _failureCodeFor(output),
      failurePhase: _failurePhaseFor(output),
      failureMessage: _failureMessageFor(output),
    );
  }

  String? _failureCodeFor(AgentActionProcessResult output) {
    if (output.status == AgentActionExecutionStatus.succeeded) {
      return null;
    }

    final elevatedFailureCode = output.failureCode?.trim();
    if (elevatedFailureCode != null && elevatedFailureCode.isNotEmpty) {
      return elevatedFailureCode;
    }

    return switch (output.status) {
      AgentActionExecutionStatus.timedOut => AgentActionFailureCode.executionTimedOut,
      AgentActionExecutionStatus.killed => AgentActionFailureCode.executionKilled,
      AgentActionExecutionStatus.failed => AgentActionFailureCode.exitCodeRejected,
      AgentActionExecutionStatus.unknown => AgentActionFailureCode.runtimeUnknown,
      _ => AgentActionFailureCode.runtimeError,
    };
  }

  String? _failureMessageFor(AgentActionProcessResult output) {
    if (output.status == AgentActionExecutionStatus.succeeded) {
      return null;
    }

    final elevatedFailureMessage = output.failureMessage?.trim();
    if (elevatedFailureMessage != null && elevatedFailureMessage.isNotEmpty) {
      return elevatedFailureMessage;
    }

    return switch (output.status) {
      AgentActionExecutionStatus.timedOut => 'Command exceeded the maximum execution time.',
      AgentActionExecutionStatus.killed => 'Main process was terminated.',
      AgentActionExecutionStatus.failed => 'Command exited with code ${output.exitCode}.',
      AgentActionExecutionStatus.unknown => 'Command ended without a known exit code.',
      _ => 'Failed to execute action.',
    };
  }

  String? _failurePhaseFor(AgentActionProcessResult output) {
    return switch (output.status) {
      AgentActionExecutionStatus.succeeded => null,
      AgentActionExecutionStatus.timedOut => 'timeout',
      AgentActionExecutionStatus.killed => 'cancel',
      AgentActionExecutionStatus.failed => 'process_exit',
      AgentActionExecutionStatus.unknown => 'process_runtime',
      _ => 'process_runtime',
    };
  }

  String? _failurePhaseForFailure(ActionFailure failure) {
    final contextPhase = failure.context['phase'];
    if (contextPhase is String && contextPhase.trim().isNotEmpty) {
      return contextPhase;
    }

    return switch (failure.code) {
      AgentActionFailureCode.elevatedSubmitFailed ||
      AgentActionFailureCode.elevatedNotConfigured ||
      AgentActionFailureCode.elevatedRequestProtectionFailed => AgentActionProcessConstants.elevatedSubmitPhase,
      _ => switch (failure) {
        ActionQueueFailure() => 'queue',
        ActionTimeoutFailure() => 'timeout',
        ActionAuthorizationFailure() => 'authorization',
        ActionValidationFailure() => 'validation',
        ActionRuntimeFailure() => 'process_runtime',
        ActionNotFoundFailure() => 'lookup',
        _ => null,
      },
    };
  }

  int _utf8ByteLength(String? text) {
    if (text == null) {
      return 0;
    }
    return utf8.encode(text).length;
  }

  void _recordLocalAuthorizationDeniedIfApplicable(Object exception) {
    if (exception is ActionAuthorizationFailure) {
      _metrics?.recordLocalAuthorizationDenied();
    }
  }
}

class _StartedAgentActionExecution {
  const _StartedAgentActionExecution({
    required this.queuedExecution,
    required this.completion,
  });

  final AgentActionExecution queuedExecution;
  final Future<Result<AgentActionExecution>> completion;
}
