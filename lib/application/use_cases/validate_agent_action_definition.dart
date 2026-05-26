import 'package:json_schema/json_schema.dart';
import 'package:plug_agente/application/actions/action_environment_resolver.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_execution_validator.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

class ValidateAgentActionDefinition {
  const ValidateAgentActionDefinition(
    this._adapterRegistry, {
    AgentActionSecretPlaceholderResolver? secretPlaceholderResolver,
    AgentActionRuntimeExecutionValidator? runtimeExecutionValidator,
    ActionEnvironmentResolver? environmentResolver,
  }) : _secretPlaceholderResolver = secretPlaceholderResolver,
       _runtimeExecutionValidator = runtimeExecutionValidator ?? const AgentActionRuntimeExecutionValidator(),
       _environmentResolver = environmentResolver ?? const ActionEnvironmentResolver();

  final AgentActionAdapterRegistry _adapterRegistry;
  final AgentActionSecretPlaceholderResolver? _secretPlaceholderResolver;
  final AgentActionRuntimeExecutionValidator _runtimeExecutionValidator;
  final ActionEnvironmentResolver _environmentResolver;

  Future<Result<AgentActionPreflight>> call(
    AgentActionDefinition definition,
  ) async {
    final basicValidationFailure = _validateBasicDefinition(definition);
    if (basicValidationFailure != null) {
      return Failure(basicValidationFailure);
    }

    final secretGateResult = await _secretPlaceholderResolver?.ensureResolvable(definition);
    if (secretGateResult != null && secretGateResult.isError()) {
      return Failure(secretGateResult.exceptionOrNull()!);
    }

    final adapterResult = _adapterRegistry.resolve(definition.type);
    return adapterResult.fold(
      (adapter) => adapter.validateDefinition(definition),
      (failure) async => Failure(failure),
    );
  }

  Future<Result<AgentActionDefinition>> normalizeForSave(
    AgentActionDefinition definition,
  ) async {
    final validationResult = await call(definition);
    if (validationResult.isError()) {
      return Failure(validationResult.exceptionOrNull()!);
    }

    final adapterResult = _adapterRegistry.resolve(definition.type);
    return adapterResult.fold(
      (adapter) => adapter.normalizeDefinition(definition),
      (failure) async => Failure(failure),
    );
  }

  ActionValidationFailure? _validateBasicDefinition(
    AgentActionDefinition definition,
  ) {
    if (definition.id.trim().isEmpty) {
      return ActionValidationFailure.withContext(
        message: 'Action id is required.',
        context: const {
          'field': 'id',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.fieldRequiredReason,
          'user_message': 'Informe o identificador da acao antes de salvar.',
        },
      );
    }

    if (definition.name.trim().isEmpty) {
      return ActionValidationFailure.withContext(
        message: 'Action name is required.',
        context: const {
          'field': 'name',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.fieldRequiredReason,
          'user_message': 'Informe o nome da acao antes de salvar.',
        },
      );
    }

    if (definition.definitionVersion < 1) {
      return ActionValidationFailure.withContext(
        message: 'Action definition version must be greater than zero.',
        context: const {
          'field': 'definitionVersion',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.invalidVersionReason,
          'user_message': 'A versao da definicao da acao e invalida.',
        },
      );
    }

    if (definition.policies.queue.maxConcurrent < 1) {
      return ActionValidationFailure.withContext(
        message: 'Action maxConcurrent must be greater than zero.',
        context: const {
          'field': 'queue.maxConcurrent',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.invalidQueuePolicyReason,
          'user_message': 'O limite de execucoes simultaneas deve ser maior que zero.',
        },
      );
    }

    if (definition.policies.queue.maxQueued < 0) {
      return ActionValidationFailure.withContext(
        message: 'Action maxQueued cannot be negative.',
        context: const {
          'field': 'queue.maxQueued',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.invalidQueuePolicyReason,
          'user_message': 'O limite da fila nao pode ser negativo.',
        },
      );
    }

    if (definition.policies.timeout.maxRuntime <= Duration.zero) {
      return ActionValidationFailure.withContext(
        message: 'Action maxRuntime must be greater than zero.',
        context: const {
          'field': 'timeout.maxRuntime',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.invalidTimeoutPolicyReason,
          'user_message': 'O tempo maximo de execucao deve ser maior que zero.',
        },
      );
    }

    if (definition.policies.elevated.runElevated && definition.policies.retry.maxAttempts > 1) {
      return ActionValidationFailure.withContext(
        message: 'Elevated actions cannot configure automatic retry.',
        context: const {
          'field': 'retry.maxAttempts',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.elevatedRetryNotAllowedReason,
          'user_message': 'Acoes com execucao elevada (UAC) nao podem usar mais de uma tentativa automatica.',
        },
      );
    }

    final deploymentCeilingFailure = _validateDeploymentPolicyCeilings(definition);
    if (deploymentCeilingFailure != null) {
      return deploymentCeilingFailure;
    }

    if (_containsBlankEntry(definition.policies.path.allowedWorkingDirectories)) {
      return ActionValidationFailure.withContext(
        message: 'Action allowedWorkingDirectories cannot contain blank entries.',
        context: const {
          'field': 'path.allowedWorkingDirectories',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.invalidPathPolicyReason,
          'user_message': 'Remova diretorios vazios da lista permitida de diretorios de trabalho.',
        },
      );
    }

    if (_containsBlankEntry(definition.policies.path.allowedContextDirectories)) {
      return ActionValidationFailure.withContext(
        message: 'Action allowedContextDirectories cannot contain blank entries.',
        context: const {
          'field': 'path.allowedContextDirectories',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.invalidPathPolicyReason,
          'user_message': 'Remova diretorios vazios da lista permitida de arquivos de contexto.',
        },
      );
    }

    final contextJsonSchemaFailure = _validateContextJsonSchema(
      definition.policies.context.contextJsonSchema,
    );
    if (contextJsonSchemaFailure != null) {
      return contextJsonSchemaFailure;
    }

    final runtimeParameterSchemaFailure = _runtimeExecutionValidator.validateRuntimeParameterSchemaDefinition(
      definition.policies.context.runtimeParameterSchema,
    );
    if (runtimeParameterSchemaFailure != null) {
      return runtimeParameterSchemaFailure;
    }

    if (_containsBlankEntry(definition.policies.environment.allowedVariableNames)) {
      return ActionValidationFailure.withContext(
        message: 'Action allowedVariableNames cannot contain blank entries.',
        context: const {
          'field': 'environment.allowedVariableNames',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.invalidEnvironmentVariableNameReason,
          'user_message': 'Remova nomes vazios da lista permitida de variaveis de ambiente.',
        },
      );
    }

    final environmentPolicyFailure = _environmentResolver.validatePolicy(
      actionId: definition.id,
      policy: definition.policies.environment,
    );
    if (environmentPolicyFailure != null) {
      return environmentPolicyFailure;
    }

    return null;
  }

  ActionValidationFailure? _validateDeploymentPolicyCeilings(AgentActionDefinition definition) {
    final policies = definition.policies;
    final maxConcurrent = AgentActionPolicyDefaults.maxConcurrentActions;
    if (policies.queue.maxConcurrent > maxConcurrent) {
      return _policyCeilingFailure(
        field: 'queue.maxConcurrent',
        configured: policies.queue.maxConcurrent,
        ceiling: maxConcurrent,
        userMessage: 'O limite de execucoes simultaneas excede o teto deste agente ($maxConcurrent).',
      );
    }

    final maxQueued = AgentActionPolicyDefaults.maxQueuedActions;
    if (policies.queue.maxQueued > maxQueued) {
      return _policyCeilingFailure(
        field: 'queue.maxQueued',
        configured: policies.queue.maxQueued,
        ceiling: maxQueued,
        userMessage: 'O tamanho maximo da fila excede o teto deste agente ($maxQueued).',
      );
    }

    final queueTimeoutCeiling = AgentActionPolicyDefaults.defaultQueueTimeout;
    if (policies.queue.queueTimeout > queueTimeoutCeiling) {
      return _policyCeilingFailure(
        field: 'queue.queueTimeout',
        configured: policies.queue.queueTimeout.inSeconds,
        ceiling: queueTimeoutCeiling.inSeconds,
        userMessage: 'O timeout da fila excede o teto deste agente (${queueTimeoutCeiling.inSeconds}s).',
      );
    }

    final maxRuntimeCeiling = AgentActionPolicyDefaults.defaultMaxRuntime;
    if (policies.timeout.maxRuntime > maxRuntimeCeiling) {
      return _policyCeilingFailure(
        field: 'timeout.maxRuntime',
        configured: policies.timeout.maxRuntime.inSeconds,
        ceiling: maxRuntimeCeiling.inSeconds,
        userMessage: 'O tempo maximo de execucao excede o teto deste agente (${maxRuntimeCeiling.inSeconds}s).',
      );
    }

    final maxRetries = AgentActionPolicyDefaults.maxRetryAttempts;
    if (policies.retry.maxAttempts > maxRetries) {
      return _policyCeilingFailure(
        field: 'retry.maxAttempts',
        configured: policies.retry.maxAttempts,
        ceiling: maxRetries,
        userMessage: 'O numero de tentativas excede o teto deste agente ($maxRetries).',
      );
    }

    final maxContextBytes = AgentActionPolicyDefaults.maxContextBytes;
    if (policies.context.maxContextBytes > maxContextBytes) {
      return _policyCeilingFailure(
        field: 'context.maxContextBytes',
        configured: policies.context.maxContextBytes,
        ceiling: maxContextBytes,
        userMessage: 'O tamanho maximo de contexto excede o teto deste agente ($maxContextBytes bytes).',
      );
    }

    final maxCapturedOutputBytes = AgentActionPolicyDefaults.maxCapturedOutputBytes;
    if (policies.capture.maxCapturedOutputBytes > maxCapturedOutputBytes) {
      return _policyCeilingFailure(
        field: 'capture.maxCapturedOutputBytes',
        configured: policies.capture.maxCapturedOutputBytes,
        ceiling: maxCapturedOutputBytes,
        userMessage: 'O limite de captura de saida excede o teto deste agente ($maxCapturedOutputBytes bytes).',
      );
    }

    return null;
  }

  ActionValidationFailure _policyCeilingFailure({
    required String field,
    required int configured,
    required int ceiling,
    required String userMessage,
  }) {
    return ActionValidationFailure.withContext(
      message: 'Action policy exceeds deployment ceiling.',
      context: {
        'field': field,
        'configured': configured,
        'ceiling': ceiling,
        'phase': AgentActionProcessConstants.definitionValidationPhase,
        'reason': AgentActionValidationConstants.policyDeploymentCeilingExceededReason,
        'user_message': userMessage,
      },
    );
  }

  bool _containsBlankEntry(Set<String> values) {
    return values.any((value) => value.trim().isEmpty);
  }

  ActionValidationFailure? _validateContextJsonSchema(
    Map<String, Object?>? schemaDefinition,
  ) {
    if (schemaDefinition == null) {
      return null;
    }

    try {
      JsonSchema.create(schemaDefinition);
      return null;
    } on FormatException catch (error) {
      return _invalidContextJsonSchemaFailure(error);
    }
  }

  ActionValidationFailure _invalidContextJsonSchemaFailure(Object error) {
    return ActionValidationFailure.withContext(
      message: 'Action context JSON schema is invalid.',
      cause: error,
      context: const {
        'field': 'context.contextJsonSchema',
        'phase': AgentActionProcessConstants.definitionValidationPhase,
        'reason': AgentActionValidationConstants.invalidContextJsonSchemaDefinitionReason,
        'user_message': 'Corrija o schema JSON de contexto antes de salvar a acao.',
      },
    );
  }
}
