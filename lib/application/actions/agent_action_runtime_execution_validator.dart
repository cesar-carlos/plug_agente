import 'package:json_schema/json_schema.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Validates runtime execution input ([AgentActionExecutionRequest]) against action policies.
class AgentActionRuntimeExecutionValidator {
  const AgentActionRuntimeExecutionValidator();

  Result<void> validateForExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    String phase = 'execution_preflight',
  }) {
    final contextPolicy = definition.policies.context;
    final injectionFailure = _validateContextInjection(
      actionId: definition.id,
      policy: contextPolicy,
      request: request,
      phase: phase,
    );
    if (injectionFailure != null) {
      return Failure(injectionFailure);
    }

    final runtimeSchemaFailure = _validateRuntimeParametersAgainstSchema(
      actionId: definition.id,
      schemaDefinition: contextPolicy.runtimeParameterSchema,
      runtimeParameters: request.runtimeParameters,
      phase: phase,
    );
    if (runtimeSchemaFailure != null) {
      return Failure(runtimeSchemaFailure);
    }

    return const Success(unit);
  }

  ActionValidationFailure? validateRuntimeParameterSchemaDefinition(
    Map<String, Object?>? schemaDefinition,
  ) {
    if (schemaDefinition == null) {
      return null;
    }

    try {
      JsonSchema.create(schemaDefinition);
      return null;
    } on FormatException catch (error) {
      return ActionValidationFailure.withContext(
        message: 'Action runtime parameter JSON schema is invalid.',
        cause: error,
        context: const {
          'field': 'context.runtimeParameterSchema',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
          'reason': AgentActionValidationConstants.invalidRuntimeParameterSchemaDefinitionReason,
          'user_message': 'Corrija o schema JSON de parametros runtime antes de salvar a acao.',
        },
      );
    }
  }

  ActionValidationFailure? _validateContextInjection({
    required String actionId,
    required AgentActionContextPolicy policy,
    required AgentActionExecutionRequest request,
    required String phase,
  }) {
    final contextPath = request.contextPath?.trim();
    final hasContextPath = contextPath != null && contextPath.isNotEmpty;

    return switch (policy.injectionMode) {
      AgentActionContextInjectionMode.file when !hasContextPath => ActionValidationFailure.withContext(
        message: 'Context file path is required for file injection mode.',
        context: {
          'action_id': actionId,
          'field': 'contextPath',
          'phase': phase,
          'injection_mode': policy.injectionMode.name,
          'reason': AgentActionValidationConstants.contextInjectionRequiresFileReason,
          'user_message': 'Informe o arquivo de contexto exigido pelo modo de injecao desta acao.',
        },
      ),
      AgentActionContextInjectionMode.stdin when hasContextPath => ActionValidationFailure.withContext(
        message: 'Context file path is not supported for stdin injection mode.',
        context: {
          'action_id': actionId,
          'field': 'contextPath',
          'phase': phase,
          'injection_mode': policy.injectionMode.name,
          'reason': AgentActionValidationConstants.contextInjectionRejectsFileReason,
          'user_message': 'Remova o arquivo de contexto: o modo stdin nao usa path de arquivo.',
        },
      ),
      AgentActionContextInjectionMode.stdin when !_hasStdinPayload(request) =>
        ActionValidationFailure.withContext(
          message: 'Stdin injection requires a non-empty runtime stdin payload.',
          context: {
            'action_id': actionId,
            'field': 'runtimeParameters.${AgentActionProcessConstants.stdinRuntimeParameterKey}',
            'phase': phase,
            'injection_mode': policy.injectionMode.name,
            'reason': AgentActionValidationConstants.contextInjectionRequiresStdinPayloadReason,
            'user_message':
                'Informe o texto de entrada padrao em runtimeParameters.stdin antes de executar.',
          },
        ),
      AgentActionContextInjectionMode.environment when hasContextPath =>
        ActionValidationFailure.withContext(
          message: 'Context file path is not supported for environment injection mode.',
          context: {
            'action_id': actionId,
            'field': 'contextPath',
            'phase': phase,
            'injection_mode': policy.injectionMode.name,
            'reason': AgentActionValidationConstants.contextInjectionRejectsFileReason,
            'user_message':
                'Remova o arquivo de contexto: o modo de variaveis de ambiente usa parametros runtime.',
          },
        ),
      _ => null,
    };
  }

  bool _hasStdinPayload(AgentActionExecutionRequest request) {
    final value = request.runtimeParameters[AgentActionProcessConstants.stdinRuntimeParameterKey];
    return value is String && value.trim().isNotEmpty;
  }

  ActionValidationFailure? _validateRuntimeParametersAgainstSchema({
    required String actionId,
    required Map<String, Object?>? schemaDefinition,
    required Map<String, Object?> runtimeParameters,
    required String phase,
  }) {
    if (schemaDefinition == null) {
      return null;
    }

    try {
      final schema = JsonSchema.create(schemaDefinition);
      final validation = schema.validate(runtimeParameters, validateFormats: false);
      if (validation.isValid) {
        return null;
      }

      return ActionValidationFailure.withContext(
        message: 'Runtime parameters do not match the configured schema.',
        context: {
          'action_id': actionId,
          'field': 'runtimeParameters',
          'phase': phase,
          'reason': AgentActionValidationConstants.runtimeParametersSchemaMismatchReason,
          'schema_error_count': validation.errors.length,
          'schema_errors': validation.errors
              .take(5)
              .map(
                (error) => '${error.instancePath.isEmpty ? '# (root)' : error.instancePath}: ${error.message}',
              )
              .toList(growable: false),
          'user_message': 'Os parametros runtime desta execucao estao fora do formato esperado pela acao.',
        },
      );
    } on FormatException catch (error) {
      return ActionValidationFailure.withContext(
        message: 'Action runtime parameter JSON schema is invalid.',
        cause: error,
        context: {
          'action_id': actionId,
          'field': 'context.runtimeParameterSchema',
          'phase': phase,
          'reason': AgentActionValidationConstants.invalidRuntimeParameterSchemaDefinitionReason,
          'user_message': 'O schema JSON de parametros runtime configurado na acao e invalido.',
        },
      );
    }
  }
}
