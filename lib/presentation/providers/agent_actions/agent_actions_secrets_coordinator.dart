import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_secrets_controller.dart';
import 'package:result_dart/result_dart.dart';

/// Secret save/delete/refresh flows for the selected agent action definition.
final class AgentActionsSecretsCoordinator {
  AgentActionsSecretsCoordinator({
    required AgentActionsSecretsController secretsController,
    required AgentActionDefinition? Function() selectedDefinition,
  }) : _secretsController = secretsController,
       _selectedDefinition = selectedDefinition;

  final AgentActionsSecretsController _secretsController;
  final AgentActionDefinition? Function() _selectedDefinition;

  bool isActionSecretConfigured(String secretName) => _secretsController.isActionSecretConfigured(secretName);

  bool isSavingActionSecret(String secretName) => _secretsController.isSavingActionSecret(secretName);

  bool isDeletingActionSecret(String secretName) => _secretsController.isDeletingActionSecret(secretName);

  void clearSecretOperationError() => _secretsController.clearSecretOperationError();

  Future<void> refreshForSelection() => _secretsController.refreshForDefinition(_selectedDefinition());

  Future<Result<Unit>> saveActionSecret({
    required String secretName,
    required String secretValue,
  }) => _secretsController.saveActionSecret(
    secretName: secretName,
    secretValue: secretValue,
    selectedDefinition: _selectedDefinition(),
  );

  Future<Result<Unit>> deleteActionSecret(String secretName) => _secretsController.deleteActionSecret(
    secretName: secretName,
    selectedDefinition: _selectedDefinition(),
  );

  Set<String> secretPlaceholderNamesFor(AgentActionDefinition definition) =>
      AgentActionSecretPlaceholderScanner.collectFromDefinition(definition);
}
