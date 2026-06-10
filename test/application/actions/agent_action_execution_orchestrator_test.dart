import 'package:plug_agente/application/actions/agent_action_execution_gate_chain.dart';
import 'package:plug_agente/application/actions/agent_action_execution_orchestrator.dart';
import 'package:plug_agente/application/actions/agent_action_prepared_execution_cache.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_prepare_execution_resolver.dart';

import '../../helpers/agent_action_use_case_test_support.dart';

void main() {
  late FakeAgentActionRepository repository;

  setUp(() {
    setUpAgentActionUseCaseTests();
    repository = agentActionUseCaseTestRepository;
  });

  group('AgentActionExecutionOrchestrator', () {
    test('should reuse persisted execution by idempotency key without starting runner', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'persisted-key',
        finishedAt: DateTime(2026, 5, 15, 9, 1),
      );
      final runner = ControlledAgentActionLocalRunner();
      final orchestrator = AgentActionExecutionOrchestrator(
        repository,
        const Uuid(),
      );

      final result = await orchestrator.run(
        gatedContext: AgentActionGatedExecutionContext(
          definition: repository.definitions['action-1']!,
          runner: runner,
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'persisted-key',
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'execution-1');
      expect(runner.startedCount, 0);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should report wouldReplay on validateRemoteAdmission for in-flight idempotency key', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-in-flight',
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final orchestrator = AgentActionExecutionOrchestrator(
        repository,
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );
      const request = AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-in-flight',
        returnWhenQueued: true,
      );
      final gatedContext = AgentActionGatedExecutionContext(
        definition: repository.definitions['action-1']!,
        runner: runner,
      );

      await orchestrator.run(
        gatedContext: gatedContext,
        request: request,
      );
      await waitForRunnerStarts(runner, 1);

      final validateResult = await orchestrator.validateRemoteAdmission(
        gatedContext: gatedContext,
        request: request,
      );

      expect(validateResult.isSuccess(), isTrue);
      final summary = validateResult.getOrThrow();
      expect(summary.wouldReplayExistingExecution, isTrue);
      expect(summary.existingExecutionId, isNull);
      expect(summary.definitionSnapshotHash, 'snap-in-flight');

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });

    test('should cache prepareExecution between validateRemoteAdmission and run for Hub requests', () async {
      final adapter = _CountingCommandLineActionAdapter();
      final runner = _PrepareAwareTestRunner(adapter: adapter);
      final cache = AgentActionPreparedExecutionCache();
      final gateChain = AgentActionExecutionGateChain(
        repository: repository,
        runnerRegistry: AgentActionLocalRunnerRegistry([runner]),
      );
      final orchestrator = AgentActionExecutionOrchestrator(
        repository,
        const Uuid(),
        preparedExecutionCache: cache,
        now: () => DateTime(2026, 5, 15, 9),
      );
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-prepare-cache',
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      const request = AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-prepare-cache',
      );
      final gatedContext = AgentActionGatedExecutionContext(
        definition: repository.definitions['action-1']!,
        runner: runner,
      );
      final adapterRegistry = AgentActionAdapterRegistry([adapter]);

      final validateResult = await orchestrator.validateRemoteAdmission(
        gatedContext: gatedContext,
        request: request,
        adapterPrepareCheck: ({
          required AgentActionDefinition definition,
          required AgentActionExecutionRequest request,
        }) {
          return gateChain.evaluateAdapterPrepare(
            definition: definition,
            request: request,
            adapterRegistry: adapterRegistry,
          );
        },
      );

      expect(validateResult.isSuccess(), isTrue);
      expect(adapter.prepareCallCount, 1);

      final runResult = await orchestrator.run(
        gatedContext: gatedContext,
        request: request,
      );

      expect(runResult.isSuccess(), isTrue);
      expect(adapter.prepareCallCount, 1);
      expect(runner.resolvedPreparedCount, 1);
    });

    test('should miss prepare cache when definition snapshot hash changes before run', () async {
      final adapter = _CountingCommandLineActionAdapter();
      final runner = _PrepareAwareTestRunner(adapter: adapter);
      final cache = AgentActionPreparedExecutionCache();
      final gateChain = AgentActionExecutionGateChain(
        repository: repository,
        runnerRegistry: AgentActionLocalRunnerRegistry([runner]),
      );
      final orchestrator = AgentActionExecutionOrchestrator(
        repository,
        const Uuid(),
        preparedExecutionCache: cache,
        now: () => DateTime(2026, 5, 15, 9),
      );
      var definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-before',
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      repository.definitions['action-1'] = definition;
      const request = AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-stale-snapshot',
      );
      final adapterRegistry = AgentActionAdapterRegistry([adapter]);
      Future<Result<AgentActionPreparedExecution>> prepareCheck({
        required AgentActionDefinition definition,
        required AgentActionExecutionRequest request,
      }) {
        return gateChain.evaluateAdapterPrepare(
          definition: definition,
          request: request,
          adapterRegistry: adapterRegistry,
        );
      }

      await orchestrator.validateRemoteAdmission(
        gatedContext: AgentActionGatedExecutionContext(definition: definition, runner: runner),
        request: request,
        adapterPrepareCheck: prepareCheck,
      );
      expect(adapter.prepareCallCount, 1);

      definition = definition.copyWith(definitionSnapshotHash: 'snap-after');
      repository.definitions['action-1'] = definition;

      final runResult = await orchestrator.run(
        gatedContext: AgentActionGatedExecutionContext(definition: definition, runner: runner),
        request: request,
      );

      expect(runResult.isSuccess(), isTrue);
      expect(adapter.prepareCallCount, 2);
    });

    test('should expire prepare cache after ttl before run', () async {
      final adapter = _CountingCommandLineActionAdapter();
      final runner = _PrepareAwareTestRunner(adapter: adapter);
      var now = DateTime(2026, 5, 15, 9);
      final cache = AgentActionPreparedExecutionCache(
        ttl: const Duration(seconds: 30),
        now: () => now,
      );
      final gateChain = AgentActionExecutionGateChain(
        repository: repository,
        runnerRegistry: AgentActionLocalRunnerRegistry([runner]),
      );
      final orchestrator = AgentActionExecutionOrchestrator(
        repository,
        const Uuid(),
        preparedExecutionCache: cache,
        now: () => now,
      );
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-ttl',
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      const request = AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-ttl',
      );
      final gatedContext = AgentActionGatedExecutionContext(
        definition: repository.definitions['action-1']!,
        runner: runner,
      );
      final adapterRegistry = AgentActionAdapterRegistry([adapter]);

      await orchestrator.validateRemoteAdmission(
        gatedContext: gatedContext,
        request: request,
        adapterPrepareCheck: ({
          required AgentActionDefinition definition,
          required AgentActionExecutionRequest request,
        }) {
          return gateChain.evaluateAdapterPrepare(
            definition: definition,
            request: request,
            adapterRegistry: adapterRegistry,
          );
        },
      );
      expect(adapter.prepareCallCount, 1);

      now = now.add(const Duration(minutes: 3));

      final runResult = await orchestrator.run(
        gatedContext: gatedContext,
        request: request,
      );

      expect(runResult.isSuccess(), isTrue);
      expect(adapter.prepareCallCount, 2);
    });
  });
}

class _CountingCommandLineActionAdapter implements AgentActionAdapter {
  int prepareCallCount = 0;

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: definition.canRun,
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    prepareCallCount++;
    return Success(
      AgentActionPreparedExecution(
        actionType: type,
        redactedCommandPreview: 'cmd.exe /C ***',
        contextHash: 'ctx-hash-$prepareCallCount',
      ),
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(definition);
  }
}

class _PrepareAwareTestRunner implements AgentActionLocalRunner {
  _PrepareAwareTestRunner({required this.adapter});

  final _CountingCommandLineActionAdapter adapter;
  int resolvedPreparedCount = 0;

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final preparedResult = await resolvePreparedExecution(
      adapter: adapter,
      definition: definition,
      request: request,
    );
    if (preparedResult.isError()) {
      return Failure(preparedResult.exceptionOrNull()!);
    }
    resolvedPreparedCount++;

    return Success(
      AgentActionProcessResult(
        status: AgentActionExecutionStatus.succeeded,
        pid: 1234,
        exitCode: 0,
        processStartedAt: DateTime(2026, 5, 15, 10),
        finishedAt: DateTime(2026, 5, 15, 10, 1),
        stdout: AgentActionCapturedOutput.disabled,
        stderr: AgentActionCapturedOutput.disabled,
        redactionApplied: true,
        contextHash: preparedResult.getOrThrow().contextHash,
      ),
    );
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) async {
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.killed,
        killed: true,
        pid: expectedPid,
        message: 'Processo principal finalizado.',
      ),
    );
  }
}
