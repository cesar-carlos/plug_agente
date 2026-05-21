import 'package:plug_agente/core/constants/agent_action_com_object_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

abstract final class ComObjectArgumentValidator {
  static Result<Map<String, Object?>> validate({
    required String actionId,
    required Map<String, Object?> arguments,
    String phase = 'definition_validation',
  }) {
    if (arguments.length > AgentActionComObjectConstants.maxArgumentEntries) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'COM object argument map exceeds the configured limit.',
          context: {
            'action_id': actionId,
            'field': 'arguments',
            'phase': phase,
            'max_entries': AgentActionComObjectConstants.maxArgumentEntries,
            'reason': AgentActionComObjectConstants.invalidArgumentsReason,
            'user_message': 'A quantidade de argumentos COM excede o limite permitido para esta acao.',
          },
        ),
      );
    }

    final normalized = <String, Object?>{};
    for (final entry in arguments.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || key.length > AgentActionComObjectConstants.maxArgumentKeyLength) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'COM object argument key is invalid.',
            context: {
              'action_id': actionId,
              'field': 'arguments',
              'phase': phase,
              'reason': AgentActionComObjectConstants.invalidArgumentsReason,
              'user_message': 'Informe chaves de argumento COM validas.',
            },
          ),
        );
      }

      final valueResult = _validateValue(
        actionId: actionId,
        key: key,
        value: entry.value,
        phase: phase,
      );
      if (valueResult.isError()) {
        return Failure(valueResult.exceptionOrNull()!);
      }

      normalized[key] = valueResult.getOrThrow();
    }

    return Success(Map<String, Object?>.unmodifiable(normalized));
  }

  static Result<Object?> _validateValue({
    required String actionId,
    required String key,
    required Object? value,
    required String phase,
  }) {
    if (value is bool) {
      return Success(value);
    }
    if (value is int) {
      return Success(value);
    }
    if (value is double) {
      return Success(value);
    }
    if (value is String) {
      if (value.length > AgentActionComObjectConstants.maxStringArgumentLength) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'COM object string argument is too long.',
            context: {
              'action_id': actionId,
              'field': 'arguments',
              'argument_key': key,
              'phase': phase,
              'reason': AgentActionComObjectConstants.invalidArgumentsReason,
              'user_message': 'Um argumento COM de texto excede o tamanho maximo permitido.',
            },
          ),
        );
      }

      return Success(value);
    }

    if (value == null) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'COM object null argument values are not supported.',
          context: {
            'action_id': actionId,
            'field': 'arguments',
            'argument_key': key,
            'phase': phase,
            'reason': AgentActionComObjectConstants.invalidArgumentsReason,
            'user_message': 'Argumentos COM nao aceitam valor nulo nesta versao.',
          },
        ),
      );
    }

    return Failure(
      ActionValidationFailure.withContext(
        message: 'COM object argument value type is not supported.',
        context: {
          'action_id': actionId,
          'field': 'arguments',
          'argument_key': key,
          'value_type': value.runtimeType.toString(),
          'phase': phase,
          'reason': AgentActionComObjectConstants.invalidArgumentsReason,
          'user_message':
              'Argumentos COM suportam apenas texto, numero e booleano nesta versao.',
        },
      ),
    );
  }
}
