import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_save_coordinator.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class _MockSaveDefinition extends Mock implements SaveAgentActionDefinition {}

class _MockDeleteDefinition extends Mock implements DeleteAgentActionDefinition {}

class _MockListDeveloperConnections extends Mock implements ListDeveloperData7Connections {}

class _MockListExecutions extends Mock implements ListAgentActionExecutions {}

class _MockRunAction extends Mock implements RunAgentActionLocally {}

class _MockTestDefinition extends Mock implements TestAgentActionDefinition {}

class _MockPreviewDefinition extends Mock implements PreviewAgentActionDefinition {}

class _MockCancelExecution extends Mock implements CancelAgentActionExecution {}

class _MockUuid extends Mock implements Uuid {}

void main() {
  final fixedNow = DateTime.utc(2026, 6, 10, 12);

  setUpAll(() {
    registerFallbackValue(
      const DeveloperData7ConnectionLookupRequest(
        actionId: 'fallback-action',
        data7ConfigPath: AgentActionPathReference(originalPath: r'C:\Data7\bin\Data7.Config'),
      ),
    );
    registerFallbackValue(
      const AgentActionDefinition(
        id: 'fallback-definition',
        name: 'Fallback',
        config: CommandLineActionConfig(command: 'dir'),
      ),
    );
  });

  late _MockSaveDefinition saveDefinition;
  late _MockDeleteDefinition deleteDefinition;
  late _MockListDeveloperConnections listDeveloperConnections;
  late _MockUuid uuid;
  late int stateChangeCount;
  late AgentActionsDefinitionsController controller;

  AgentActionsDefinitionsController buildController({
    AgentActionPreflightSettings? preflightSettings,
    DateTime Function()? now,
  }) {
    return AgentActionsDefinitionsController(
      saveDefinition: saveDefinition,
      deleteDefinition: deleteDefinition,
      listDeveloperData7Connections: listDeveloperConnections,
      uuid: uuid,
      messageFor: (failure) => failure.toString(),
      onStateChanged: () => stateChangeCount++,
      preflightSettings: preflightSettings,
      now: now ?? () => fixedNow,
    );
  }

  AgentActionDefinition definitionWithValidPreflight({
    String id = 'action-1',
    String name = 'Run',
    String command = 'dir',
    AgentActionState state = AgentActionState.active,
  }) {
    final base = AgentActionDefinition(
      id: id,
      name: name,
      state: state,
      config: CommandLineActionConfig(command: command),
    );
    final hash = controller.preflightContentSnapshotHash(base);
    return base.copyWith(
      lastPreflightSnapshotHash: hash,
      lastPreflightValidatedAt: fixedNow.subtract(const Duration(days: 1)),
    );
  }

  setUp(() {
    saveDefinition = _MockSaveDefinition();
    deleteDefinition = _MockDeleteDefinition();
    listDeveloperConnections = _MockListDeveloperConnections();
    uuid = _MockUuid();
    stateChangeCount = 0;
    controller = buildController();
  });

  group('AgentActionsDefinitionsController filters', () {
    setUp(() {
      controller.replaceDefinitions(const [
        AgentActionDefinition(
          id: 'cmd',
          name: 'Backup command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'dir'),
        ),
        AgentActionDefinition(
          id: 'email',
          name: 'Notify ops',
          state: AgentActionState.paused,
          config: EmailActionConfig(
            smtpProfileId: 'smtp-local',
            from: 'agent@example.com',
            to: <String>['ops@example.com'],
            subjectTemplate: 'Done',
            bodyTemplate: 'Finished',
          ),
        ),
      ]);
    });

    test('filters definitions by type, state and search query', () {
      controller.setDefinitionTypeFilter(AgentActionType.email);
      expect(controller.filteredDefinitions().map((d) => d.id), ['email']);

      controller.setDefinitionTypeFilter(null);
      controller.setDefinitionStateFilter(AgentActionState.paused);
      expect(controller.filteredDefinitions().map((d) => d.id), ['email']);

      controller.setDefinitionStateFilter(null);
      controller.setDefinitionSearchQuery('backup');
      expect(controller.filteredDefinitions().map((d) => d.id), ['cmd']);
    });

    test('keeps selected definition visible when list filters hide it', () {
      controller.selectAction('cmd');
      controller.setDefinitionTypeFilter(AgentActionType.email);

      expect(controller.filteredDefinitions().map((d) => d.id), ['cmd', 'email']);
    });

    test('caches filtered definitions until filters change', () {
      final first = controller.filteredDefinitions();
      final second = controller.filteredDefinitions();
      expect(identical(first, second), isTrue);

      controller.setDefinitionSearchQuery('notify');
      final third = controller.filteredDefinitions();
      expect(identical(first, third), isFalse);
    });

    test('clearDefinitionFilters resets filters and notifies listeners', () {
      controller
        ..setDefinitionTypeFilter(AgentActionType.email)
        ..setDefinitionSearchQuery('ops');
      stateChangeCount = 0;

      controller.clearDefinitionFilters();

      expect(controller.hasDefinitionListFilters, isFalse);
      expect(controller.filteredDefinitions(), hasLength(2));
      expect(stateChangeCount, 1);
    });

    test('ignores redundant filter updates', () {
      controller
        ..setDefinitionTypeFilter(AgentActionType.email)
        ..setDefinitionSearchQuery('ops');
      stateChangeCount = 0;

      controller.setDefinitionTypeFilter(AgentActionType.email);
      controller.setDefinitionSearchQuery('ops');
      controller.setDefinitionSearchQuery('  ops  ');

      expect(stateChangeCount, 0);
      expect(controller.definitionSearchQuery, 'ops');
    });
  });

  group('AgentActionsDefinitionsController selection and guards', () {
    test('selectAction notifies only when selection changes', () {
      controller.selectAction('action-1');
      expect(controller.selectedActionId, 'action-1');
      expect(stateChangeCount, 1);

      controller.selectAction('action-1');
      expect(stateChangeCount, 1);
    });

    test('resolveSelectedActionId falls back to first definition', () {
      controller.replaceDefinitions(const [
        AgentActionDefinition(
          id: 'first',
          name: 'First',
          config: CommandLineActionConfig(command: 'dir'),
        ),
        AgentActionDefinition(
          id: 'second',
          name: 'Second',
          config: CommandLineActionConfig(command: 'echo'),
        ),
      ]);

      expect(controller.resolveSelectedActionId(), 'first');

      controller.selectAction('missing');
      expect(controller.resolveSelectedActionId(), 'first');
    });

    test('canSaveAction and canDeleteDefinition respect flags', () {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run',
        config: CommandLineActionConfig(command: 'dir'),
      );

      expect(controller.canSaveAction(isFeatureEnabled: true), isTrue);
      expect(controller.canSaveAction(isFeatureEnabled: false), isFalse);

      controller.isDeleting = true;
      expect(
        controller.canDeleteDefinition(
          definition: definition,
          isFeatureEnabled: true,
          hasActiveExecution: false,
        ),
        isFalse,
      );

      controller.isDeleting = false;
      expect(
        controller.canDeleteDefinition(
          definition: definition,
          isFeatureEnabled: true,
          hasActiveExecution: true,
        ),
        isFalse,
      );
      expect(
        controller.canDeleteDefinition(
          definition: definition,
          isFeatureEnabled: true,
          hasActiveExecution: false,
        ),
        isTrue,
      );
    });
  });

  group('AgentActionsDefinitionsController loadDeveloperData7Connections', () {
    const lookupResult = DeveloperData7ConnectionLookupResult(
      resolvedConfigPath: AgentActionPathReference(
        originalPath: r'C:\Data7\bin\Data7.Config',
        canonicalPath: r'C:\Data7\bin\Data7.Config',
        existsAtValidation: true,
      ),
      usedDefaultLocation: false,
      connections: <DeveloperData7ConnectionOption>[
        DeveloperData7ConnectionOption(
          id: 'conn-1',
          label: 'Estacao',
          snapshotHash: 'sha256:test',
        ),
      ],
    );

    test('clears loading and populates connections on success', () async {
      when(
        () => listDeveloperConnections(any()),
      ).thenAnswer((_) async => const Success(lookupResult));
      stateChangeCount = 0;

      await controller.loadDeveloperData7Connections(
        actionId: 'developer-draft',
        data7ConfigPath: r'C:\Data7\bin\Data7.Config',
      );

      expect(controller.isLoadingDeveloperConnections, isFalse);
      expect(controller.developerConnectionLookupMessage, isNull);
      expect(controller.developerConnections, lookupResult.connections);
      expect(controller.resolvedDeveloperData7ConfigPath, r'C:\Data7\bin\Data7.Config');
      expect(controller.usedDefaultDeveloperData7ConfigPath, isFalse);
      expect(stateChangeCount, greaterThanOrEqualTo(2));
    });

    test('records usedDefaultDeveloperData7ConfigPath when lookup used default location', () async {
      const defaultLookupResult = DeveloperData7ConnectionLookupResult(
        resolvedConfigPath: AgentActionPathReference(
          originalPath: r'C:\Program Files\Data7\bin\Data7.Config',
          canonicalPath: r'C:\Program Files\Data7\bin\Data7.Config',
          existsAtValidation: true,
        ),
        usedDefaultLocation: true,
        connections: <DeveloperData7ConnectionOption>[
          DeveloperData7ConnectionOption(
            id: 'conn-1',
            label: 'Estacao',
            snapshotHash: 'sha256:test',
          ),
        ],
      );
      when(
        () => listDeveloperConnections(any()),
      ).thenAnswer((_) async => const Success(defaultLookupResult));

      await controller.loadDeveloperData7Connections(
        actionId: 'developer-draft',
        data7ConfigPath: '',
      );

      expect(controller.usedDefaultDeveloperData7ConfigPath, isTrue);
      expect(
        controller.resolvedDeveloperData7ConfigPath,
        r'C:\Program Files\Data7\bin\Data7.Config',
      );
    });

    test('clearDeveloperData7Connections resets lookup state', () {
      controller
        ..developerConnections = lookupResult.connections
        ..resolvedDeveloperData7ConfigPath = r'C:\Data7\bin\Data7.Config'
        ..usedDefaultDeveloperData7ConfigPath = true
        ..developerConnectionLookupMessage = 'stale';
      stateChangeCount = 0;

      controller.clearDeveloperData7Connections();

      expect(controller.developerConnections, isEmpty);
      expect(controller.resolvedDeveloperData7ConfigPath, isNull);
      expect(controller.usedDefaultDeveloperData7ConfigPath, isFalse);
      expect(controller.developerConnectionLookupMessage, isNull);
      expect(stateChangeCount, 1);
    });

    test('clears loading and surfaces failure message', () async {
      final failure = ActionValidationFailure(
        'Developer Data7 configuration file was not found.',
      );
      when(
        () => listDeveloperConnections(any()),
      ).thenAnswer((_) async => Failure(failure));
      stateChangeCount = 0;

      await controller.loadDeveloperData7Connections(
        actionId: 'developer-draft',
        data7ConfigPath: r'C:\Missing\Data7.Config',
      );

      expect(controller.isLoadingDeveloperConnections, isFalse);
      expect(controller.developerConnections, isEmpty);
      expect(controller.developerConnectionLookupMessage, failure.toString());
      expect(stateChangeCount, greaterThanOrEqualTo(2));
    });

    test('clears loading when lookup throws unexpectedly', () async {
      when(
        () => listDeveloperConnections(any()),
      ).thenThrow(StateError('gateway unavailable'));
      stateChangeCount = 0;

      await controller.loadDeveloperData7Connections(
        actionId: 'developer-draft',
        data7ConfigPath: r'C:\Data7\bin\Data7.Config',
      );

      expect(controller.isLoadingDeveloperConnections, isFalse);
      expect(controller.developerConnections, isEmpty);
      expect(controller.developerConnectionLookupMessage, isNotNull);
      expect(stateChangeCount, greaterThanOrEqualTo(2));
    });
  });

  group('AgentActionsDefinitionsController deleteSelectedAction', () {
    const definition = AgentActionDefinition(
      id: 'action-1',
      name: 'Run',
      config: CommandLineActionConfig(command: 'dir'),
    );

    test('surfaces delete failure in lastOperationErrorMessage', () async {
      final failure = ActionNotFoundFailure('Action was not found.');
      when(() => deleteDefinition('action-1')).thenAnswer((_) async => Failure(failure));

      final result = await controller.deleteSelectedAction(
        definition: definition,
        canDelete: true,
      );

      expect(result.shouldReload, isFalse);
      expect(result.errorMessage, failure.toString());
      expect(controller.lastOperationErrorMessage, failure.toString());
      expect(controller.isDeleting, isFalse);
      expect(stateChangeCount, greaterThanOrEqualTo(2));
    });

    test('returns shouldReload when delete succeeds', () async {
      when(() => deleteDefinition('action-1')).thenAnswer((_) async => const Success(unit));

      final result = await controller.deleteSelectedAction(
        definition: definition,
        canDelete: true,
      );

      expect(result.shouldReload, isTrue);
      expect(result.errorMessage, isNull);
      expect(controller.selectedActionId, isNull);
    });

    test('skips delete when canDelete is false', () async {
      final result = await controller.deleteSelectedAction(
        definition: definition,
        canDelete: false,
      );

      expect(result.shouldReload, isFalse);
      verifyNever(() => deleteDefinition(any()));
    });
  });

  group('AgentActionsSaveCoordinator saveCommandLineAction', () {
    late AgentActionsSaveCoordinator saveCoordinator;

    AgentActionsSaveCoordinator buildSaveCoordinator() {
      final executionsController = AgentActionsExecutionsController(
        listExecutions: _MockListExecutions(),
        runAction: _MockRunAction(),
        testDefinition: _MockTestDefinition(),
        previewDefinition: _MockPreviewDefinition(),
        cancelExecution: _MockCancelExecution(),
        messageFor: (failure) => failure.toString(),
        onStateChanged: () {},
      );
      return AgentActionsSaveCoordinator(
        definitionsController: controller,
        executionsController: executionsController,
        saveDefinition: saveDefinition,
        uuid: uuid,
        now: () => fixedNow,
        messageFor: (failure) => failure.toString(),
        reload: () async {},
        setErrorMessage: (_) {},
      );
    }

    setUp(() {
      saveCoordinator = buildSaveCoordinator();
    });

    test('skips save when canSave is false', () async {
      final saved = await saveCoordinator.saveCommandLineAction(
        name: 'Run',
        command: 'dir',
        canSave: false,
      );

      expect(saved, isFalse);
      expect(controller.isSaving, isFalse);
      verifyNever(() => saveDefinition(any()));
    });

    test('surfaces save failure in lastOperationErrorMessage', () async {
      final failure = ActionValidationFailure('Action name is required.');
      when(() => uuid.v4()).thenReturn('new-action-id');
      when(() => saveDefinition(any())).thenAnswer((_) async => Failure(failure));
      stateChangeCount = 0;

      final saved = await saveCoordinator.saveCommandLineAction(
        name: 'Run',
        command: 'dir',
        canSave: true,
      );

      expect(saved, isFalse);
      expect(controller.isSaving, isFalse);
      expect(controller.lastOperationErrorMessage, failure.toString());
      expect(stateChangeCount, greaterThanOrEqualTo(2));
    });

    test('returns true and selects saved definition on success', () async {
      const savedDefinition = AgentActionDefinition(
        id: 'saved-action',
        name: 'Run',
        config: CommandLineActionConfig(command: 'dir'),
      );
      when(() => uuid.v4()).thenReturn('saved-action');
      when(() => saveDefinition(any())).thenAnswer((_) async => const Success(savedDefinition));

      final saved = await saveCoordinator.saveCommandLineAction(
        name: 'Run',
        command: 'dir',
        canSave: true,
      );

      expect(saved, isTrue);
      expect(controller.isSaving, isFalse);
      expect(controller.selectedActionId, 'saved-action');
      expect(controller.lastOperationErrorMessage, isNull);
    });

    test('preserves session preflight metadata when updating existing definition', () async {
      final existing = definitionWithValidPreflight();
      controller.replaceDefinitions([existing]);
      controller
        ..sessionPreflightSnapshotHashes[existing.id] = existing.lastPreflightSnapshotHash!
        ..sessionPreflightValidatedAt[existing.id] = existing.lastPreflightValidatedAt!;

      when(() => saveDefinition(any())).thenAnswer((invocation) async {
        final definition = invocation.positionalArguments.first as AgentActionDefinition;
        expect(definition.lastPreflightSnapshotHash, existing.lastPreflightSnapshotHash);
        expect(definition.lastPreflightValidatedAt, existing.lastPreflightValidatedAt);
        return Success(definition);
      });

      final saved = await saveCoordinator.saveCommandLineAction(
        name: 'Updated name',
        command: 'dir',
        actionId: 'action-1',
        canSave: true,
      );

      expect(saved, isTrue);
      verify(() => saveDefinition(any())).called(1);
    });
  });

  group('AgentActionsDefinitionsController preflight session', () {
    late AgentActionPreflightSettings preflightSettings;

    setUp(() {
      preflightSettings = AgentActionPreflightSettings(InMemoryAppSettingsStore());
      controller = buildController(preflightSettings: preflightSettings);
    });

    test('syncSessionPreflightSnapshotHashes copies valid persisted preflight only', () {
      final valid = definitionWithValidPreflight(id: 'valid');
      final staleHash = valid.copyWith(
        id: 'stale-hash',
        lastPreflightSnapshotHash: 'sha256:stale',
      );
      final missingTimestamp = valid.copyWith(
        id: 'missing-timestamp',
        lastPreflightValidatedAt: null,
      );
      controller.replaceDefinitions([valid, staleHash, missingTimestamp]);

      controller.syncSessionPreflightSnapshotHashes(
        isPreflightValid: controller.isPreflightValidForDefinition,
      );

      expect(controller.sessionPreflightSnapshotHashes.keys, ['valid']);
      expect(
        controller.sessionPreflightSnapshotHashes['valid'],
        valid.lastPreflightSnapshotHash,
      );
      expect(
        controller.sessionPreflightValidatedAt['valid'],
        valid.lastPreflightValidatedAt,
      );
    });

    test('isPreflightValidForDefinition uses session overrides over persisted values', () {
      final definition = definitionWithValidPreflight();
      controller.replaceDefinitions([definition]);
      final sessionHash = controller.preflightContentSnapshotHash(definition);
      final sessionValidatedAt = fixedNow;
      controller
        ..sessionPreflightSnapshotHashes[definition.id] = sessionHash
        ..sessionPreflightValidatedAt[definition.id] = sessionValidatedAt;

      expect(controller.isPreflightValidForDefinition(definition), isTrue);
    });

    test('isPreflightExpiredForDefinition is true when hash matches but TTL elapsed', () {
      final definition = definitionWithValidPreflight();
      final expiredValidatedAt = fixedNow.subtract(
        AgentActionPolicyDefaults.preflightValidityDuration + const Duration(days: 1),
      );
      final expired = definition.copyWith(lastPreflightValidatedAt: expiredValidatedAt);
      controller.replaceDefinitions([expired]);

      expect(controller.isPreflightValidForDefinition(expired), isFalse);
      expect(controller.isPreflightExpiredForDefinition(expired), isTrue);
      expect(
        controller.preflightExpiresAtForDefinition(expired),
        expiredValidatedAt.add(AgentActionPolicyDefaults.preflightValidityDuration),
      );
    });

    test('canSetDefinitionActive requires valid preflight and rejects draft changes', () {
      final definition = definitionWithValidPreflight();
      controller.replaceDefinitions([definition]);

      expect(
        controller.canSetDefinitionActive(definition.id, draftModified: false),
        isTrue,
      );
      expect(
        controller.canSetDefinitionActive(definition.id, draftModified: true),
        isFalse,
      );
      expect(
        controller.canSetDefinitionActive('missing', draftModified: false),
        isFalse,
      );
    });

    test('recordPreflightSuccess updates session and definition list on success', () async {
      final definition = definitionWithValidPreflight().copyWith(
        state: AgentActionState.needsValidation,
      );
      controller.replaceDefinitions([definition]);
      when(() => saveDefinition(any())).thenAnswer((invocation) async {
        final updated = invocation.positionalArguments.first as AgentActionDefinition;
        return Success(updated.copyWith(state: AgentActionState.active));
      });
      stateChangeCount = 0;

      final errorMessage = await controller.recordPreflightSuccess(definition);

      expect(errorMessage, isNull);
      expect(controller.lastOperationErrorMessage, isNull);
      expect(controller.sessionPreflightSnapshotHashes[definition.id], isNotNull);
      expect(controller.sessionPreflightValidatedAt[definition.id], fixedNow);
      expect(controller.definitions.single.state, AgentActionState.active);
      expect(stateChangeCount, greaterThanOrEqualTo(1));
    });

    test('recordPreflightSuccess surfaces save failure without updating definitions', () async {
      final definition = definitionWithValidPreflight();
      controller.replaceDefinitions([definition]);
      final failure = ActionValidationFailure('Unable to persist preflight result.');
      when(() => saveDefinition(any())).thenAnswer((_) async => Failure(failure));
      stateChangeCount = 0;

      final errorMessage = await controller.recordPreflightSuccess(definition);

      expect(errorMessage, failure.toString());
      expect(controller.lastOperationErrorMessage, failure.toString());
      expect(controller.definitions.single.state, AgentActionState.active);
      expect(stateChangeCount, greaterThanOrEqualTo(1));
    });

    test('clearPreflightSessionForDefinition removes session entries', () {
      controller
        ..sessionPreflightSnapshotHashes['action-1'] = 'sha256:test'
        ..sessionPreflightValidatedAt['action-1'] = fixedNow;

      controller.clearPreflightSessionForDefinition('action-1');

      expect(controller.sessionPreflightSnapshotHashes, isEmpty);
      expect(controller.sessionPreflightValidatedAt, isEmpty);
    });
  });
}
