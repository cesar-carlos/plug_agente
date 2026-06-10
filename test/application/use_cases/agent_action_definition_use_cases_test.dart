import '../../helpers/agent_action_use_case_test_support.dart';

void main() {
  late FakeAgentActionRepository repository;
  late ValidateAgentActionDefinition validateDefinition;
  late FeatureFlags featureFlags;

  setUp(() {
    setUpAgentActionUseCaseTests();
    repository = agentActionUseCaseTestRepository;
    validateDefinition = agentActionUseCaseValidateDefinition;
    featureFlags = agentActionUseCaseFeatureFlags;
  });

  group('agent action definition use cases', () {
    test('should save valid definition after adapter validation', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      final saved = repository.definitions['action-1']!;
      expect(saved.definitionSnapshotHash, startsWith('sha256:'));
      expect(result.getOrThrow().definitionSnapshotHash, saved.definitionSnapshotHash);
    });

    test('should reject saving active definition without successful preflight', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final result = await useCase(definition);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).code,
        AgentActionFailureCode.preflightRequiredForActive,
      );
      expect(repository.definitions, isEmpty);
    });

    test('should allow saving active definition after preflight hash is recorded', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().state, AgentActionState.active);
      expect(result.getOrThrow().lastPreflightSnapshotHash, isNotNull);
    });

    test('should reject saving active definition when preflight validation expired', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
        now: () => DateTime.utc(2026, 6, 25),
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final staged = await useCase(definition.copyWith(state: AgentActionState.needsValidation));
      expect(staged.isSuccess(), isTrue);

      const snapshotter = AgentActionDefinitionSnapshotter();
      final preflightHash = snapshotter.snapshotHash(
        definition.copyWith(state: AgentActionState.needsValidation),
      );
      repository.definitions['action-1'] = staged.getOrThrow().copyWith(
        lastPreflightSnapshotHash: preflightHash,
        lastPreflightValidatedAt: DateTime.utc(2026, 4),
      );

      final result = await useCase(
        repository.definitions['action-1']!.copyWith(state: AgentActionState.active),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).code,
        AgentActionFailureCode.preflightExpiredForActive,
      );
    });

    test('should invalidate preflight hash when definition content changes on save', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final first = await saveDefinitionForTest(useCase, definition);
      expect(first.isSuccess(), isTrue);

      final activeWithoutPreflight = await useCase(
        first.getOrThrow().copyWith(
          config: const CommandLineActionConfig(command: 'dir /b'),
          lastPreflightSnapshotHash: first.getOrThrow().lastPreflightSnapshotHash,
        ),
      );

      expect(activeWithoutPreflight.isError(), isTrue);
      expect(
        (activeWithoutPreflight.exceptionOrNull()! as ActionValidationFailure).code,
        AgentActionFailureCode.preflightRequiredForActive,
      );
    });

    test('should clear runElevated when elevated feature flag is disabled', () async {
      await featureFlags.setEnableElevatedAgentActions(false);
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-elevated',
        name: 'Elevated action',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().policies.elevated.runElevated, isFalse);
    });

    test('should require remote reapproval on save when secret reference fingerprint changes', () async {
      final secretStore = InMemoryAgentActionSecretStoreForRunTests();
      await secretStore.saveSecret('api', 'v1');
      const snapshotter = AgentActionDefinitionSnapshotter();
      final fingerprinter = AgentActionSecretReferenceFingerprinter(secretStore);
      const base = AgentActionDefinition(
        id: 'action-secret',
        name: 'Secret cmd',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: r'echo ${secret:api}'),
      );
      final approvedAt = DateTime.utc(2026, 5, 20, 9);
      final initialFingerprints = await fingerprinter.fingerprintsFor(base);
      final preflightHash = snapshotter.snapshotHash(
        base.copyWith(state: AgentActionState.needsValidation),
      );
      repository.definitions['action-secret'] = base.copyWith(
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: approvedAt,
            approvedBy: 'local-ui',
            riskFingerprint: snapshotter.riskFingerprint(
              base,
              secretReferenceFingerprints: initialFingerprints,
            ),
          ),
        ),
        lastPreflightSnapshotHash: preflightHash,
      );

      await secretStore.saveSecret('api', 'v2');
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        snapshotter,
        featureFlags,
        secretReferenceFingerprinter: fingerprinter,
      );
      final result = await useCase(
        base.copyWith(
          state: AgentActionState.needsValidation,
          lastPreflightSnapshotHash: null,
          policies: AgentActionDefinitionPolicies(
            remote: AgentActionRemotePolicy(
              isEnabled: true,
              approvedAt: approvedAt,
              approvedBy: 'local-ui',
            ),
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().policies.remote.requiresReapproval, isTrue);
      expect(result.getOrThrow().policies.remote.canRunSavedAction, isFalse);
    });

    test('should clear allowAdHoc when remote ad-hoc feature flag is disabled', () async {
      await featureFlags.setEnableRemoteAdHocAgentActions(false);
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      final definition = AgentActionDefinition(
        id: 'action-adhoc',
        name: 'Remote ad-hoc',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            allowAdHoc: true,
            approvedAt: DateTime.utc(2026, 5, 19),
            approvedBy: 'local-ui',
          ),
        ),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().policies.remote.allowAdHoc, isFalse);
    });

    test('should trim definition id and name when saving', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: '  action-x  ',
        name: '  Run  ',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'action-x');
      expect(result.getOrThrow().name, 'Run');
      expect(repository.definitions['action-x'], isNotNull);
      expect(repository.definitions.containsKey('  action-x  '), isFalse);
    });

    test('should reject saving remote-approved definition when app-close trigger exists', () async {
      repository.triggers['t1'] = const AgentActionTrigger(
        id: 't1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      final definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026),
          ),
        ),
      );

      final result = await useCase(definition);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.definitions, isEmpty);
    });

    test('should save remote-enabled definition when app-close exists but reapproval is required', () async {
      repository.triggers['t1'] = const AgentActionTrigger(
        id: 't1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      final definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026),
            requiresReapproval: true,
          ),
        ),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(repository.definitions['action-1'], isNotNull);
    });

    test('should not save invalid definition', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );

      final result = await useCase(
        const AgentActionDefinition(
          id: 'action-1',
          name: '',
          config: CommandLineActionConfig(command: 'dir'),
        ),
      );

      expect(result.isError(), isTrue);
      expect(repository.definitions, isEmpty);
    });

    test('should require remote reapproval when risk fingerprint changes on save', () async {
      const snapshotter = AgentActionDefinitionSnapshotter();
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        snapshotter,
        featureFlags,
      );
      final approvedAt = DateTime.utc(2026, 5, 19, 10);
      final initial = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: approvedAt,
            approvedBy: 'local-ui',
          ),
        ),
      );

      final first = await saveDefinitionForTest(useCase, initial);
      expect(first.isSuccess(), isTrue);
      expect(first.getOrThrow().policies.remote.canRunSavedAction, isTrue);

      final changed = first.getOrThrow().copyWith(
        config: const CommandLineActionConfig(command: 'dir /b'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: approvedAt,
            approvedBy: 'local-ui',
          ),
        ),
        state: AgentActionState.needsValidation,
        lastPreflightSnapshotHash: null,
      );

      final staged = await useCase(changed);
      expect(staged.isSuccess(), isTrue);
      final preflightHash = snapshotter.snapshotHash(
        staged.getOrThrow().copyWith(state: AgentActionState.needsValidation),
      );
      final second = await useCase(
        staged.getOrThrow().copyWith(
          state: AgentActionState.active,
          lastPreflightSnapshotHash: preflightHash,
        ),
      );

      expect(second.isSuccess(), isTrue);
      final remote = second.getOrThrow().policies.remote;
      expect(remote.requiresReapproval, isTrue);
      expect(remote.canRunSavedAction, isFalse);
    });

    test('should change definition snapshot hash when relevant definition fields change', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const baseDefinition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final first = await saveDefinitionForTest(useCase, baseDefinition);
      final second = await saveDefinitionForTest(
        useCase,
        baseDefinition.copyWith(
          config: const CommandLineActionConfig(command: 'dir /b'),
        ),
      );

      expect(first.isSuccess(), isTrue);
      expect(second.isSuccess(), isTrue);
      expect(
        first.getOrThrow().definitionSnapshotHash,
        isNot(equals(second.getOrThrow().definitionSnapshotHash)),
      );
    });

    test('should persist normalized path metadata before hashing definition', () async {
      final validatingUseCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(
            normalizedDefinitionFactory: (definition) {
              final config = definition.config as CommandLineActionConfig;
              return definition.copyWith(
                config: CommandLineActionConfig(
                  command: config.command,
                  workingDirectory: AgentActionPathReference(
                    originalPath: r'C:\Jobs',
                    canonicalPath: r'C:\Canonical\Jobs',
                    existsAtValidation: true,
                    validatedAt: DateTime.utc(2026, 5, 15, 12),
                  ),
                ),
              );
            },
          ),
        ]),
      );
      final useCase = SaveAgentActionDefinition(
        repository,
        validatingUseCase,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );

      final result = await saveDefinitionForTest(
        useCase,
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Run command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(
            command: 'dir',
            workingDirectory: AgentActionPathReference(
              originalPath: r'C:\Jobs',
            ),
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      final saved = repository.definitions['action-1']!;
      final config = saved.config as CommandLineActionConfig;
      expect(config.workingDirectory?.canonicalPath, r'C:\Canonical\Jobs');
      expect(config.workingDirectory?.existsAtValidation, isTrue);
      expect(config.workingDirectory?.validatedAt, DateTime.utc(2026, 5, 15, 12));
      expect(saved.definitionSnapshotHash, startsWith('sha256:'));
    });

    test('should get, list and delete definitions through repository', () async {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.definitions[definition.id] = definition;

      final getResult = await GetAgentActionDefinition(repository)('action-1');
      final listResult = await ListAgentActionDefinitions(repository)();
      final deleteResult = await DeleteAgentActionDefinition(repository)('action-1');

      expect(getResult.getOrThrow(), definition);
      expect(listResult.getOrThrow(), [definition]);
      expect(deleteResult.isSuccess(), isTrue);
      expect(repository.definitions, isEmpty);
    });

    test('should test saved definition without executing action', () async {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.definitions[definition.id] = definition;
      final useCase = TestAgentActionDefinition(
        repository,
        validateDefinition,
      );

      final result = await useCase('action-1');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().actionType, AgentActionType.commandLine);
      expect(result.getOrThrow().canRun, isTrue);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject test definition with empty action id', () async {
      final useCase = TestAgentActionDefinition(
        repository,
        validateDefinition,
      );

      final result = await useCase(' ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.savedExecutions, isEmpty);
    });

    test('should return not found failure when deleting missing definition', () async {
      final result = await DeleteAgentActionDefinition(repository)('missing');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
    });

    test('should reject delete definition with blank id', () async {
      final result = await DeleteAgentActionDefinition(repository)('  \t');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim action id when deleting definition', () async {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.definitions[definition.id] = definition;

      final result = await DeleteAgentActionDefinition(repository)('  action-1  ');

      expect(result.isSuccess(), isTrue);
      expect(repository.definitions, isEmpty);
    });

    test('should reject get definition with blank id', () async {
      final result = await GetAgentActionDefinition(repository)('  \t');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim id when getting definition', () async {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.definitions[definition.id] = definition;

      final result = await GetAgentActionDefinition(repository)('  action-1  ');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'action-1');
    });
  });
}
