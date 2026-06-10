import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_secret_availability_checker.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_secret.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_secrets_controller.dart';
import 'package:result_dart/result_dart.dart';

class _MockSaveSecret extends Mock implements SaveAgentActionSecret {}

class _MockDeleteSecret extends Mock implements DeleteAgentActionSecret {}

void main() {
  late _FakeAgentActionSecretStore secretStore;
  late AgentActionSecretAvailabilityChecker availabilityChecker;
  late _MockSaveSecret saveSecret;
  late _MockDeleteSecret deleteSecret;
  late int stateChangeCount;
  late AgentActionsSecretsController controller;

  const definition = AgentActionDefinition(
    id: 'action-1',
    name: 'Run',
    config: CommandLineActionConfig(command: r'echo ${secret:db_password}'),
  );

  AgentActionsSecretsController buildController({
    SaveAgentActionSecret? save,
    DeleteAgentActionSecret? delete,
  }) {
    return AgentActionsSecretsController(
      secretAvailabilityChecker: availabilityChecker,
      saveAgentActionSecret: save,
      deleteAgentActionSecret: delete,
      messageFor: (failure) => failure.toString(),
      onStateChanged: () => stateChangeCount++,
    );
  }

  setUp(() {
    secretStore = _FakeAgentActionSecretStore(existing: {'other_secret'});
    availabilityChecker = AgentActionSecretAvailabilityChecker(secretStore: secretStore);
    saveSecret = _MockSaveSecret();
    deleteSecret = _MockDeleteSecret();
    stateChangeCount = 0;
    controller = buildController(save: saveSecret, delete: deleteSecret);
  });

  group('AgentActionsSecretsController availability', () {
    test('refreshForDefinition clears report when definition is null', () async {
      controller.selectedSecretReport = const AgentActionSecretAvailabilityReport(
        referencedSecretNames: {'db_password'},
      );
      stateChangeCount = 0;

      await controller.refreshForDefinition(null);

      expect(controller.selectedSecretReport, isNull);
      expect(stateChangeCount, 1);
    });

    test('refreshForDefinition reports missing referenced secrets', () async {
      await controller.refreshForDefinition(definition);

      expect(controller.selectedSecretPlaceholderNames, {'db_password'});
      expect(controller.selectedMissingSecretNames, {'db_password'});
      expect(controller.isActionSecretConfigured('db_password'), isFalse);
      expect(controller.isActionSecretConfigured('other_secret'), isFalse);
    });

    test('isActionSecretConfigured returns true for configured secrets', () async {
      secretStore.existing.add('db_password');
      await controller.refreshForDefinition(definition);

      expect(controller.isActionSecretConfigured('db_password'), isTrue);
      expect(controller.selectedMissingSecretNames, isEmpty);
    });
  });

  group('AgentActionsSecretsController saveActionSecret', () {
    test('saves secret and refreshes availability report', () async {
      when(
        () => saveSecret(
          secretName: any(named: 'secretName'),
          secretValue: any(named: 'secretValue'),
        ),
      ).thenAnswer((invocation) async {
        final secretName = invocation.namedArguments[#secretName]! as String;
        secretStore.existing.add(secretName.trim());
        return const Success(unit);
      });

      final result = await controller.saveActionSecret(
        secretName: 'db_password',
        secretValue: 'secret-value',
        selectedDefinition: definition,
      );

      expect(result.isSuccess(), isTrue);
      expect(controller.secretOperationErrorMessage, isNull);
      expect(controller.isSavingActionSecret('db_password'), isFalse);
      expect(controller.selectedMissingSecretNames, isEmpty);
      expect(stateChangeCount, greaterThanOrEqualTo(2));
    });

    test('surfaces save failure in secretOperationErrorMessage', () async {
      final failure = ActionValidationFailure('Secret value is required.');
      when(
        () => saveSecret(
          secretName: any(named: 'secretName'),
          secretValue: any(named: 'secretValue'),
        ),
      ).thenAnswer((_) async => Failure(failure));

      final result = await controller.saveActionSecret(
        secretName: 'db_password',
        secretValue: '',
        selectedDefinition: definition,
      );

      expect(result.isError(), isTrue);
      expect(controller.secretOperationErrorMessage, failure.toString());
    });

    test('returns validation failure when secret store is unavailable', () async {
      final unavailableController = AgentActionsSecretsController(
        secretAvailabilityChecker: AgentActionSecretAvailabilityChecker(
          secretStore: _FakeAgentActionSecretStore(existing: {}),
        ),
        saveAgentActionSecret: null,
        deleteAgentActionSecret: null,
        messageFor: (failure) => failure.toString(),
        onStateChanged: () {},
      );

      final result = await unavailableController.saveActionSecret(
        secretName: 'db_password',
        secretValue: 'value',
        selectedDefinition: definition,
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain_errors.ValidationFailure>());
      expect(unavailableController.isActionSecretStoreAvailable, isFalse);
    });
  });

  group('AgentActionsSecretsController deleteActionSecret', () {
    test('deletes secret and refreshes availability report', () async {
      secretStore.existing.add('db_password');
      await controller.refreshForDefinition(definition);
      when(() => deleteSecret('db_password')).thenAnswer((_) async {
        secretStore.existing.remove('db_password');
        return const Success(unit);
      });

      final result = await controller.deleteActionSecret(
        secretName: 'db_password',
        selectedDefinition: definition,
      );

      expect(result.isSuccess(), isTrue);
      expect(controller.secretOperationErrorMessage, isNull);
      expect(controller.selectedMissingSecretNames, {'db_password'});
    });

    test('surfaces delete failure in secretOperationErrorMessage', () async {
      final failure = ActionRuntimeFailure('Delete failed.');
      when(() => deleteSecret('db_password')).thenAnswer((_) async => Failure(failure));

      final result = await controller.deleteActionSecret(
        secretName: 'db_password',
        selectedDefinition: definition,
      );

      expect(result.isError(), isTrue);
      expect(controller.secretOperationErrorMessage, failure.toString());
    });

    test('clearSecretOperationError notifies listeners', () {
      controller.secretOperationErrorMessage = 'Persist failed';
      stateChangeCount = 0;

      controller.clearSecretOperationError();

      expect(controller.secretOperationErrorMessage, isNull);
      expect(stateChangeCount, 1);
    });
  });
}

class _FakeAgentActionSecretStore implements IAgentActionSecretStore {
  _FakeAgentActionSecretStore({required this.existing});

  final Set<String> existing;

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretName) async {
    existing.remove(secretName);
  }

  @override
  Future<String?> readSecret(String secretName) async {
    return existing.contains(secretName) ? 'configured' : null;
  }

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    existing.add(secretName);
  }

  @override
  Future<bool> exists(String secretName) async => existing.contains(secretName);
}
