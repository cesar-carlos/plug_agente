import 'package:plug_agente/core/constants/agent_action_email_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

abstract final class AgentActionEmailAddressValidator {
  static final RegExp _emailPattern = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    '[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
  );

  static final RegExp _templateTokenPattern = RegExp(r'\{\{[^{}]+\}\}');

  static bool containsTemplateTokens(String value) => _templateTokenPattern.hasMatch(value);

  static Result<String> validateAddress({
    required String actionId,
    required String field,
    required String address,
    String phase = 'definition_validation',
  }) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email address cannot be empty.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'reason': AgentActionEmailConstants.invalidEmailAddressReason,
            'user_message': 'Informe um endereco de e-mail valido.',
          },
        ),
      );
    }

    if (containsTemplateTokens(trimmed)) {
      return Success(trimmed);
    }

    if (!_emailPattern.hasMatch(trimmed)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email address is invalid.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'reason': AgentActionEmailConstants.invalidEmailAddressReason,
            'user_message': 'Informe um endereco de e-mail valido.',
          },
        ),
      );
    }

    return Success(trimmed);
  }

  static Result<List<String>> validateRecipientList({
    required String actionId,
    required String field,
    required List<String> addresses,
    required bool required,
    String phase = 'definition_validation',
  }) {
    if (addresses.isEmpty) {
      if (required) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'At least one email recipient is required.',
            context: {
              'action_id': actionId,
              'field': field,
              'phase': phase,
              'reason': AgentActionEmailConstants.invalidEmailAddressReason,
              'user_message': 'Informe pelo menos um destinatario valido.',
            },
          ),
        );
      }

      return const Success(<String>[]);
    }

    if (addresses.length > AgentActionEmailConstants.maxRecipientsPerList) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email recipient list exceeds the configured limit.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'max_recipients': AgentActionEmailConstants.maxRecipientsPerList,
            'reason': AgentActionEmailConstants.tooManyRecipientsReason,
            'user_message': 'A lista de destinatarios excede o limite permitido para esta acao.',
          },
        ),
      );
    }

    final normalized = <String>[];
    for (final address in addresses) {
      final validation = validateAddress(
        actionId: actionId,
        field: field,
        address: address,
        phase: phase,
      );
      if (validation.isError()) {
        return Failure(validation.exceptionOrNull()!);
      }
      normalized.add(validation.getOrThrow());
    }

    return Success(List<String>.unmodifiable(normalized));
  }
}
