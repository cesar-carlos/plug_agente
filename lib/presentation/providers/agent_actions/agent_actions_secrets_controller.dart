import 'package:plug_agente/application/actions/agent_action_secret_availability_checker.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_secret.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:result_dart/result_dart.dart';

typedef AgentActionsSecretsStateChanged = void Function();

class AgentActionsSecretsController {
  AgentActionsSecretsController({
    required AgentActionSecretAvailabilityChecker secretAvailabilityChecker,
    required SaveAgentActionSecret? saveAgentActionSecret,
    required DeleteAgentActionSecret? deleteAgentActionSecret,
    required String Function(Exception failure) messageFor,
    required AgentActionsSecretsStateChanged onStateChanged,
  }) : _secretAvailabilityChecker = secretAvailabilityChecker,
       _saveAgentActionSecret = saveAgentActionSecret,
       _deleteAgentActionSecret = deleteAgentActionSecret,
       _messageFor = messageFor,
       _onStateChanged = onStateChanged;

  final AgentActionSecretAvailabilityChecker _secretAvailabilityChecker;
  final SaveAgentActionSecret? _saveAgentActionSecret;
  final DeleteAgentActionSecret? _deleteAgentActionSecret;
  final String Function(Exception failure) _messageFor;
  final AgentActionsSecretsStateChanged _onStateChanged;

  AgentActionSecretAvailabilityReport? selectedSecretReport;
  String? savingActionSecretName;
  String? deletingActionSecretName;
  String? secretOperationErrorMessage;

  bool get isActionSecretStoreAvailable =>
      _saveAgentActionSecret != null && _deleteAgentActionSecret != null;

  Set<String> get selectedSecretPlaceholderNames =>
      selectedSecretReport?.referencedSecretNames ?? const <String>{};

  Set<String> get selectedMissingSecretNames =>
      selectedSecretReport?.missingSecretNames ?? const <String>{};

  bool isActionSecretConfigured(String secretName) {
    final report = selectedSecretReport;
    if (report == null) {
      return false;
    }
    return report.referencedSecretNames.contains(secretName) &&
        !report.missingSecretNames.contains(secretName);
  }

  bool isSavingActionSecret(String secretName) => savingActionSecretName == secretName;

  bool isDeletingActionSecret(String secretName) => deletingActionSecretName == secretName;

  void clearSecretOperationError() {
    if (secretOperationErrorMessage == null) {
      return;
    }
    secretOperationErrorMessage = null;
    _onStateChanged();
  }

  Future<void> refreshForDefinition(AgentActionDefinition? definition) async {
    if (definition == null) {
      selectedSecretReport = null;
      _onStateChanged();
      return;
    }

    selectedSecretReport = await _secretAvailabilityChecker.check(definition);
    _onStateChanged();
  }

  Future<Result<Unit>> saveActionSecret({
    required String secretName,
    required String secretValue,
    required AgentActionDefinition? selectedDefinition,
  }) async {
    final saveSecret = _saveAgentActionSecret;
    if (saveSecret == null) {
      return Failure(
        domain_errors.ValidationFailure('Action secret store is not available.'),
      );
    }

    savingActionSecretName = secretName.trim();
    secretOperationErrorMessage = null;
    _onStateChanged();

    final result = await saveSecret(
      secretName: secretName,
      secretValue: secretValue,
    );

    savingActionSecretName = null;
    result.fold(
      (_) {
        secretOperationErrorMessage = null;
      },
      (failure) {
        secretOperationErrorMessage = _messageFor(failure);
      },
    );
    await refreshForDefinition(selectedDefinition);
    return result;
  }

  Future<Result<Unit>> deleteActionSecret({
    required String secretName,
    required AgentActionDefinition? selectedDefinition,
  }) async {
    final deleteSecret = _deleteAgentActionSecret;
    if (deleteSecret == null) {
      return Failure(
        domain_errors.ValidationFailure('Action secret store is not available.'),
      );
    }

    deletingActionSecretName = secretName.trim();
    secretOperationErrorMessage = null;
    _onStateChanged();

    final result = await deleteSecret(secretName);

    deletingActionSecretName = null;
    result.fold(
      (_) {
        secretOperationErrorMessage = null;
      },
      (failure) {
        secretOperationErrorMessage = _messageFor(failure);
      },
    );
    await refreshForDefinition(selectedDefinition);
    return result;
  }
}
