import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/core/constants/agent_action_command_line_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Keeps the legacy free-form shell surface local and free of secrets.
class AgentActionCommandLinePolicyValidator {
  const AgentActionCommandLinePolicyValidator();

  Result<void> validateDefinition(AgentActionDefinition definition) {
    final config = definition.config;
    if (config is! CommandLineActionConfig ||
        AgentActionSecretPlaceholderScanner.collectFromText(config.command).isEmpty) {
      return const Success(unit);
    }
    return Failure(
      ActionValidationFailure.withContext(
        message: 'Secret placeholders are not supported in free-form command lines.',
        code: AgentActionFailureCode.commandLineSecretPlaceholderForbidden,
        context: {
          'action_id': definition.id,
          'reason': AgentActionCommandLineConstants.secretPlaceholderForbiddenReason,
          'user_message':
              'Segredos nao podem ser usados na linha de comando. Use entrada padrao ou variaveis de ambiente permitidas.',
        },
      ),
    );
  }

  Result<void> validateExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) {
    final definitionResult = validateDefinition(definition);
    if (definitionResult.isError()) return definitionResult;
    if (definition.type != AgentActionType.commandLine || request.source == AgentActionRequestSource.localUi) {
      return const Success(unit);
    }
    return Failure(
      ActionAuthorizationFailure.withContext(
        message: 'Free-form command-line actions are restricted to manual local execution.',
        code: AgentActionFailureCode.commandLineLocalOnly,
        context: {
          'action_id': definition.id,
          'source': request.source.name,
          'reason': AgentActionCommandLineConstants.localOnlyReason,
          'user_message': 'Linha de comando so pode ser executada manualmente neste agente.',
        },
      ),
    );
  }
}
