import 'package:plug_agente/core/constants/agent_action_com_object_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/utils/path_extension.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/com_object_argument_validator.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_registry.dart';
import 'package:result_dart/result_dart.dart';

class ComObjectActionAdapter implements AgentActionAdapter {
  ComObjectActionAdapter({
    required ComObjectInvocationRegistry invocationRegistry,
    ActionPathValidator? pathValidator,
  }) : _invocationRegistry = invocationRegistry,
       _pathValidator = pathValidator ?? ActionPathValidator();

  final ComObjectInvocationRegistry _invocationRegistry;
  final ActionPathValidator _pathValidator;

  @override
  AgentActionType get type => AgentActionType.comObject;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    final resolvedResult = await _resolveConfig(definition: definition);
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();
    final isRegistered = _invocationRegistry.isRegistered(
      progId: resolved.config.progId,
      memberName: resolved.config.memberName,
    );
    final canRun = definition.canRun && isRegistered;

    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: canRun,
        safeMessage: canRun
            ? 'COM object action is ready to run.'
            : isRegistered
            ? 'COM object action is valid but not active.'
            : 'COM object action is saved but this ProgID/member is not enabled on this agent.',
        redactedDiagnostics: {
          'argument_count': resolved.config.arguments.length,
          'registered_invocation': isRegistered,
        },
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final resolvedResult = await _resolveConfig(
      definition: definition,
      phase: 'execution_preflight',
      requireRegistration: true,
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();

    final contextValidation = await _pathValidator.validateContextFile(
      actionId: definition.id,
      contextPath: request.contextPath,
      policy: definition.policies.context,
      pathPolicy: definition.policies.path,
    );
    if (contextValidation.isError()) {
      return Failure(contextValidation.exceptionOrNull()!);
    }

    return Success(
      AgentActionPreparedExecution(
        actionType: type,
        redactedCommandPreview: resolved.redactedPreview,
        redactedDiagnostics: {
          'argument_count': resolved.config.arguments.length,
          'context_path_extension': extensionOf(request.contextPath),
          'uses_context_path': request.contextPath != null,
        },
      ),
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    final resolvedResult = await _resolveConfig(definition: definition);
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();

    return Success(
      definition.copyWith(
        config: ComObjectActionConfig(
          progId: resolved.config.progId,
          memberName: resolved.config.memberName,
          arguments: resolved.config.arguments,
        ),
      ),
    );
  }

  Future<Result<_ResolvedComObjectConfig>> _resolveConfig({
    required AgentActionDefinition definition,
    String phase = 'definition_validation',
    bool requireRegistration = false,
  }) async {
    final config = definition.config;
    if (config is! ComObjectActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'COM object action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.comObject.name,
            'phase': phase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao COM e invalida.',
          },
        ),
      );
    }

    final progId = config.progId.trim();
    if (progId.isEmpty || progId.length > AgentActionComObjectConstants.maxProgIdLength) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'COM ProgID is invalid.',
          context: {
            'action_id': definition.id,
            'field': 'progId',
            'phase': phase,
            'reason': AgentActionComObjectConstants.invalidProgIdReason,
            'user_message': 'Informe um ProgID COM valido para esta acao.',
          },
        ),
      );
    }

    final memberName = config.memberName.trim();
    if (memberName.isEmpty || memberName.length > AgentActionComObjectConstants.maxMemberNameLength) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'COM member name is invalid.',
          context: {
            'action_id': definition.id,
            'field': 'memberName',
            'phase': phase,
            'reason': AgentActionComObjectConstants.invalidMemberNameReason,
            'user_message': 'Informe um membro COM valido para esta acao.',
          },
        ),
      );
    }

    if (requireRegistration && !_invocationRegistry.isRegistered(progId: progId, memberName: memberName)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'COM object invocation is not registered for this agent.',
          context: {
            'action_id': definition.id,
            'prog_id': progId,
            'member_name': memberName,
            'phase': phase,
            'reason': AgentActionComObjectConstants.invocationNotRegisteredReason,
            'user_message': 'Esta combinacao de ProgID e membro COM nao esta habilitada neste agente.',
          },
        ),
      );
    }

    final argumentsResult = ComObjectArgumentValidator.validate(
      actionId: definition.id,
      arguments: config.arguments,
      phase: phase,
    );
    if (argumentsResult.isError()) {
      return Failure(argumentsResult.exceptionOrNull()!);
    }

    final normalizedConfig = ComObjectActionConfig(
      progId: progId,
      memberName: memberName,
      arguments: argumentsResult.getOrThrow(),
    );

    return Success(
      _ResolvedComObjectConfig(
        config: normalizedConfig,
        redactedPreview: 'com-object progId=[REDACTED] member=[REDACTED] args=${normalizedConfig.arguments.length}',
      ),
    );
  }

}

class _ResolvedComObjectConfig {
  const _ResolvedComObjectConfig({
    required this.config,
    required this.redactedPreview,
  });

  final ComObjectActionConfig config;
  final String redactedPreview;
}
