import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionRuntimeRequestValidator {
  const AgentActionRuntimeRequestValidator();

  Result<void> validate(AgentActionExecutionRequest request) {
    final actionId = request.actionId.trim();
    if (actionId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action id is required to run an action.',
          context: const {
            'field': 'actionId',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe a acao que sera executada.',
          },
        ),
      );
    }

    final idempotencyFailure = _validateOptionalText(
      field: 'idempotencyKey',
      value: request.idempotencyKey,
      reason: AgentActionValidationConstants.invalidIdempotencyKeyReason,
      userMessage: 'A chave de idempotencia informada para esta execucao e invalida.',
    );
    if (idempotencyFailure != null) {
      return Failure(idempotencyFailure);
    }

    final requestedByFailure = _validateOptionalText(
      field: 'requestedBy',
      value: request.requestedBy,
      reason: AgentActionValidationConstants.invalidRequestedByReason,
      userMessage: 'O identificador do solicitante desta execucao e invalido.',
    );
    if (requestedByFailure != null) {
      return Failure(requestedByFailure);
    }

    final traceIdFailure = _validateOptionalText(
      field: 'traceId',
      value: request.traceId,
      reason: AgentActionValidationConstants.invalidTraceIdReason,
      userMessage: 'O identificador de rastreio desta execucao e invalido.',
    );
    if (traceIdFailure != null) {
      return Failure(traceIdFailure);
    }

    final triggerIdFailure = _validateOptionalText(
      field: 'triggerId',
      value: request.triggerId,
      reason: AgentActionValidationConstants.invalidTriggerIdReason,
      userMessage: 'O identificador do gatilho desta execucao e invalido.',
    );
    if (triggerIdFailure != null) {
      return Failure(triggerIdFailure);
    }

    if (request.contextPath != null && request.contextPath!.trim().isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Context path cannot be empty.',
          context: const {
            'field': 'contextPath',
            'reason': AgentActionValidationConstants.invalidContextPathReason,
            'user_message': 'Informe um arquivo de contexto valido ou remova este campo.',
          },
        ),
      );
    }

    if (!_isJsonLikeMap(request.runtimeParameters)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Runtime parameters must use JSON-compatible values.',
          context: const {
            'field': 'runtimeParameters',
            'reason': AgentActionValidationConstants.invalidRuntimeParametersReason,
            'user_message': 'Os parametros runtime precisam usar apenas valores JSON compativeis.',
          },
        ),
      );
    }

    return const Success(unit);
  }

  ActionValidationFailure? _validateOptionalText({
    required String field,
    required String? value,
    required String reason,
    required String userMessage,
  }) {
    if (value == null) {
      return null;
    }
    if (value.trim().isEmpty) {
      return ActionValidationFailure.withContext(
        message: '$field cannot be empty when provided.',
        context: {
          'field': field,
          'reason': reason,
          'user_message': userMessage,
        },
      );
    }
    return null;
  }

  bool _isJsonLikeMap(Map<String, Object?> values) {
    for (final entry in values.entries) {
      if (entry.key.trim().isEmpty || !_isJsonLikeValue(entry.value)) {
        return false;
      }
    }
    return true;
  }

  bool _isJsonLikeValue(Object? value) {
    if (value == null || value is String || value is bool) {
      return true;
    }
    if (value is num) {
      return value.isFinite;
    }
    if (value is List<Object?>) {
      return value.every(_isJsonLikeValue);
    }
    if (value is Map<String, Object?>) {
      return _isJsonLikeMap(value);
    }
    if (value is Map) {
      if (value.keys.any((key) => key is! String || key.trim().isEmpty)) {
        return false;
      }
      return value.values.every(_isJsonLikeValue);
    }
    if (value is List) {
      return value.every(_isJsonLikeValue);
    }
    return false;
  }
}
