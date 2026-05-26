import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:result_dart/result_dart.dart';

class DeleteAgentActionSecret {
  const DeleteAgentActionSecret(this._secretStore);

  final IAgentActionSecretStore _secretStore;

  Future<Result<Unit>> call(String secretName) async {
    final trimmedName = secretName.trim();
    if (trimmedName.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action secret name is required.',
          context: const {
            'field': 'secretName',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o nome do segredo.',
          },
        ),
      );
    }

    if (!_secretStore.isAvailable) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action secret store is not available.',
          context: const {
            'reason': AgentActionValidationConstants.secretStoreUnavailableReason,
            'user_message': 'O armazenamento seguro de segredos nao esta disponivel neste agente.',
          },
        ),
      );
    }

    try {
      await _secretStore.deleteSecret(trimmedName);
      return const Success(unit);
    } on Object catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Failed to delete action secret.',
          cause: error,
          timestamp: DateTime.now(),
          context: {
            'secret_name': trimmedName,
            'reason': AgentActionValidationConstants.secretPersistFailedReason,
            'user_message': 'Nao foi possivel remover o segredo. Tente novamente.',
          },
        ),
      );
    }
  }
}
