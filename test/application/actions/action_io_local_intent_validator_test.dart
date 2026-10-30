import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/application/actions/action_io_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_local_intent_validator.dart';
import 'package:plug_agente/application/actions/action_io_session_launcher.dart';
import 'package:plug_agente/application/actions/action_io_session_supervisor.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_execution_gate_chain.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/repositories/i_action_io_invocation_resolver.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process_factory.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class _Repository extends Mock implements IAgentActionRepository {}

class _Secrets extends Mock implements IAgentActionSecretStore {}

class _Gates extends Mock implements AgentActionExecutionGateChain {}

class _Runner extends Mock implements AgentActionLocalRunner {}

class _Tokens extends Mock implements IClientTokenRepository {}

class _Input extends Mock implements IActionIoJournal {}

class _Output extends Mock implements IActionIoOutputJournal {}

class _Processes extends Mock implements IActionIoProcessFactory {}

class _Invocations implements IActionIoInvocationResolver {
  bool denied = false;
  @override
  Future<Result<ActionIoInvocation>> resolve(
    AgentActionDefinition definition,
    AgentActionExecutionRequest request,
  ) async {
    expect(request.runtimeParameters, isEmpty);
    expect(request.ioSession, isNull);
    return denied
        ? Failure(ActionValidationFailure('Executable path is unavailable'))
        : Success(
            ActionIoInvocation(
              executable: 'fixture.exe',
              arguments: [],
              environment: {},
              includeParentEnvironment: false,
            ),
          );
  }
}

void main() {
  setUpAll(
    () => registerFallbackValue(
      const AgentActionExecutionRequest(actionId: 'a', source: AgentActionRequestSource.remoteHub),
    ),
  );
  test('uses current saved definition, remote trigger and faithful approval', () async {
    const snapshotter = AgentActionDefinitionSnapshotter();
    final repository = _Repository();
    final gates = _Gates();
    final queue = ActionExecutionQueue();
    final invocations = _Invocations();
    var definition = AgentActionDefinition(
      id: 'action',
      name: 'Saved',
      state: AgentActionState.active,
      config: const ExecutableActionConfig(executablePath: AgentActionPathReference(originalPath: r'C:\fixture.exe')),
      policies: AgentActionDefinitionPolicies(
        remote: AgentActionRemotePolicy(
          isEnabled: true,
          allowFaithfulIo: true,
          approvedAt: DateTime.utc(2026),
        ),
      ),
    );
    definition = definition.copyWith(
      policies: definition.policies.copyWith(
        remote: definition.policies.remote.copyWith(riskFingerprint: snapshotter.riskFingerprint(definition)),
      ),
    );
    var trigger = const AgentActionTrigger(id: 'trigger', actionId: 'action', type: AgentActionTriggerType.remote);
    var gateDenied = false;
    when(() => gates.evaluate(request: any(named: 'request'), faithfulIo: true)).thenAnswer(
      (_) async => gateDenied
          ? Failure(ActionAuthorizationFailure('Maintenance is active'))
          : Success(AgentActionGatedExecutionContext(definition: definition, runner: _Runner())),
    );
    when(() => repository.getDefinition('action')).thenAnswer((_) async => Success(definition));
    when(() => repository.getTrigger('trigger')).thenAnswer((_) async => Success(trigger));
    final validator = ActionIoLocalIntentValidator(
      repository: repository,
      snapshotter: snapshotter,
      secretFingerprinter: AgentActionSecretReferenceFingerprinter(_Secrets()),
      gates: gates,
      invocations: invocations,
      queue: queue,
    );
    final intent = ActionIoSessionIntent(
      executionId: 'e',
      installationId: 'i',
      agentId: 'a',
      clientId: 'c',
      actionId: 'action',
      idempotencyKey: 'key',
      fingerprint: 'request',
      triggerId: 'trigger',
      definitionHash: snapshotter.snapshotHash(definition),
    );
    expect((await validator.validate(intent)).isSuccess(), isTrue);
    final tokens = _Tokens();
    final input = _Input();
    final output = _Output();
    final processes = _Processes();
    final supervisor = ActionIoSessionSupervisor();
    var revoked = false;
    when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer(
      (_) async => Success(
        ClientTokenSummary(
          id: 'token',
          clientId: 'c',
          agentId: 'a',
          createdAt: DateTime.utc(2026),
          isRevoked: revoked,
          allTables: false,
          allViews: false,
          rules: const [],
          payload: const {
            'agent_action_scopes': ['agent_actions.*'],
          },
        ),
      ),
    );
    when(() => input.markStarting('e')).thenAnswer((_) async {
      revoked = true;
      return const Success(unit);
    });
    when(
      () => output.finish('e', exitCode: null, complete: true, failureCode: 'ACTION_IO_UNAUTHORIZED'),
    ).thenAnswer((_) async => const Success(unit));
    final launcher = ActionIoSessionLauncher(
      authorization: ActionIoAuthorization(tokens),
      validator: validator,
      repository: repository,
      invocations: invocations,
      processes: processes,
      input: input,
      output: output,
      queue: ActionIoExecutionQueue(queue, supervisor),
    );
    final launch = await launcher.execute(
      intent,
      claim: const ActionIoSessionClaim(executionId: 'e', created: true),
      credential: 'credential',
      deadline: DateTime.now().add(const Duration(minutes: 1)),
    );
    expect(launch.isError(), isTrue);
    verify(() => input.markStarting('e')).called(1);
    verifyZeroInteractions(processes);
    expect(queue.runningCount, 0);
    expect(supervisor.isSafelyIdle, isTrue);
    (await supervisor.shutdown()).getOrThrow();
    queue.pauseAdmissionForMaintenance('maintenance');
    expect((await validator.validate(intent)).isError(), isTrue);
    queue.resumeAdmissionAfterMaintenance('maintenance');
    invocations.denied = true;
    expect((await validator.validate(intent)).exceptionOrNull(), isA<ActionValidationFailure>());
    invocations.denied = false;
    gateDenied = true;
    expect((await validator.validate(intent)).exceptionOrNull(), isA<ActionAuthorizationFailure>());
    gateDenied = false;
    trigger = trigger.copyWith(isEnabled: false);
    expect((await validator.validate(intent)).isError(), isTrue);
    trigger = trigger.copyWith(isEnabled: true, actionId: 'different-action');
    expect((await validator.validate(intent)).isError(), isTrue);
    trigger = trigger.copyWith(actionId: 'action');
    definition = definition.copyWith(name: 'Changed');
    expect((await validator.validate(intent)).isError(), isTrue);
    definition = definition.copyWith(config: const CommandLineActionConfig(command: 'echo unsupported'));
    final failure = (await validator.validate(intent)).exceptionOrNull()! as ActionValidationFailure;
    expect(failure.code, 'ACTION_IO_EXECUTOR_UNSUPPORTED');
  });
}
