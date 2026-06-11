part of '../agent_actions_provider.dart';

extension AgentActionsProviderSecretsSurface on AgentActionsProvider {
  bool isActionSecretConfigured(String secretName) => _secretsCoordinator.isActionSecretConfigured(secretName);

  bool isSavingActionSecret(String secretName) => _secretsCoordinator.isSavingActionSecret(secretName);

  bool isDeletingActionSecret(String secretName) => _secretsCoordinator.isDeletingActionSecret(secretName);

  Set<String> secretPlaceholderNamesFor(AgentActionDefinition definition) =>
      _secretsCoordinator.secretPlaceholderNamesFor(definition);

  void clearSecretOperationError() => _secretsCoordinator.clearSecretOperationError();

  Future<Result<Unit>> saveActionSecret({
    required String secretName,
    required String secretValue,
  }) => _secretsCoordinator.saveActionSecret(
    secretName: secretName,
    secretValue: secretValue,
  );

  Future<Result<Unit>> deleteActionSecret(String secretName) => _secretsCoordinator.deleteActionSecret(secretName);
}
