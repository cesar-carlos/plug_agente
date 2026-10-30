import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
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
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/repositories/i_action_io_invocation_resolver.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process_factory.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_io_process_factory.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_job_api.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart' hide ActionIoEvent;
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:result_dart/result_dart.dart';

class _Repository extends Mock implements IAgentActionRepository {}

class _Secrets extends Mock implements IAgentActionSecretStore {}

class _Gates extends Mock implements AgentActionExecutionGateChain {}

class _Runner extends Mock implements AgentActionLocalRunner {}

class _Tokens extends Mock implements IClientTokenRepository {}

class _RefusingProcesses implements IActionIoProcessFactory {
  _RefusingProcesses(this.throwsFailure, this.db);
  final bool throwsFailure;
  final ActionIoJournalDatabase db;
  int calls = 0;

  @override
  Future<Result<IActionIoProcess>> start(ActionIoInvocation invocation) async {
    calls++;
    expect((await db.select(db.actionIoSessions).getSingle()).processState, 'starting');
    if (throwsFailure) throw StateError('private native launch diagnostic');
    return Failure(
      ActionRuntimeFailure.withContext(
        message: 'Process creation outcome is unknown.',
        code: 'ACTION_OUTCOME_UNKNOWN',
      ),
    );
  }
}

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
              executable: '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
              arguments: [
                '-NoProfile',
                '-NonInteractive',
                '-Command',
                r'$i=[Console]::OpenStandardInput();$o=[Console]::OpenStandardOutput();$b=New-Object byte[] 65536;while(($n=$i.Read($b,0,$b.Length)) -gt 0){$o.Write($b,0,$n);$o.Flush()}',
              ],
              environment: {},
              includeParentEnvironment: true,
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
  for (final scenario in ['success', 'spawn_failure', 'spawn_exception', 'revoked_after_starting']) {
    test('launcher $scenario preserves durable ownership and refuses duplicate execution', () async {
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
      const trigger = AgentActionTrigger(id: 'trigger', actionId: 'action', type: AgentActionTriggerType.remote);
      when(() => gates.evaluate(request: any(named: 'request'), faithfulIo: true)).thenAnswer(
        (_) async => Success(AgentActionGatedExecutionContext(definition: definition, runner: _Runner())),
      );
      when(() => repository.getDefinition('action')).thenAnswer((_) async => Success(definition));
      when(() => repository.getTrigger('trigger')).thenAnswer((_) async => const Success(trigger));
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
        actionType: definition.type.name,
      );
      final directory = await Directory.systemTemp.createTemp('action-io-launcher-');
      final db = ActionIoJournalDatabase(NativeDatabase(File('${directory.path}/journal.sqlite')));
      final cipher = ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 7)));
      final input = DriftActionIoJournal(db, cipher);
      final output = ActionIoOutputJournal(db, cipher);
      final supervisor = ActionIoSessionSupervisor();
      try {
        final tokens = _Tokens();
        var revokedAfterStarting = false;
        when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async {
          // Revoke only after the real durable starting commit, before spawn.
          final starting = (await db.select(db.actionIoSessions).getSingle()).processState == 'starting';
          revokedAfterStarting = scenario == 'revoked_after_starting' && starting;
          return Success(
            ClientTokenSummary(
              id: 'token',
              clientId: 'c',
              agentId: 'a',
              createdAt: DateTime.utc(2026),
              isRevoked: revokedAfterStarting,
              allTables: false,
              allViews: false,
              rules: const [],
              payload: const {
                'agent_action_scopes': ['agent_actions.*'],
              },
            ),
          );
        });
        final bytes = List.generate(65536, (i) => i % 256);
        final config = ActionIoConfiguration(initialInput: bytes, closeInput: true);
        final claim = (await input.claim(intent, io: config)).getOrThrow();
        final refusing = _RefusingProcesses(scenario == 'spawn_exception', db);
        final launcher = ActionIoSessionLauncher(
          authorization: ActionIoAuthorization(tokens),
          validator: validator,
          repository: repository,
          invocations: invocations,
          processes: scenario == 'success'
              ? WindowsActionIoProcessFactory(WindowsJobObjectProcessTreeController(api: WindowsActionJobApi()))
              : refusing,
          input: input,
          output: output,
          queue: ActionIoExecutionQueue(queue, supervisor),
        );
        final launched = await launcher.execute(
          intent,
          claim: claim,
          credential: 'fixture',
          deadline: DateTime.now().add(const Duration(seconds: 20)),
        );
        if (scenario == 'revoked_after_starting') {
          expect(revokedAfterStarting, isTrue);
          expect(launched.exceptionOrNull(), isA<ActionAuthorizationFailure>());
          expect((launched.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_UNAUTHORIZED');
          expect(refusing.calls, 0);
          expect(queue.runningCount, 0);
          expect(supervisor.accepting, isTrue);
          expect((await db.select(db.actionIoSessions).getSingle()).processState, 'finished');
          final receipt = (await input.inputStatus('e', 'c', ActionIoLimits.initialMessageId)).getOrThrow();
          expect(receipt.state, ActionIoDeliveryState.failed);
          expect(receipt.confirmedBytes, 0);
          final duplicate = (await input.claim(intent, io: config)).getOrThrow();
          expect(duplicate.created, isFalse);
          final replay = await launcher.execute(
            intent,
            claim: duplicate,
            credential: 'fixture',
            deadline: DateTime.now().add(const Duration(seconds: 20)),
          );
          expect((replay.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_REPLAY_FORBIDDEN');
          expect(refusing.calls, 0);
          return;
        }
        if (scenario != 'success') {
          expect(launched.exceptionOrNull(), isA<ActionRuntimeFailure>());
          expect(refusing.calls, 1);
          expect(queue.runningCount, 1);
          expect(supervisor.accepting, isFalse);
          expect((await db.select(db.actionIoSessions).getSingle()).processState, 'starting');
          final duplicate = (await input.claim(intent, io: config)).getOrThrow();
          final replay = await launcher.execute(
            intent,
            claim: duplicate,
            credential: 'fixture',
            deadline: DateTime.now().add(const Duration(seconds: 20)),
          );
          expect((replay.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_REPLAY_FORBIDDEN');
          expect(refusing.calls, 1);
          expect((await input.reconcileInterrupted()).getOrThrow(), 1);
          expect((await input.markStarting('e')).isError(), isTrue);
          expect((await input.beginNextInput('e')).getOrThrow().input, isNull);
          return;
        }
        launched.getOrThrow();
        final row = await db.select(db.actionIoSessions).getSingle();
        expect(row.processState, 'finished');
        expect(row.actionType, definition.type.name);
        expect((await input.getSessionReference('e')).getOrThrow().actionType, definition.type.name);
        final page = (await output.read(
          executionId: 'e',
          clientId: 'c',
          afterSequence: 0,
          maxBytes: ActionIoLimits.pageBytes,
        )).getOrThrow();
        expect(page.events.whereType<ActionIoOutputEvent>().expand((e) => e.bytes).toList(), bytes);
        final receipt = (await input.inputStatus('e', 'c', ActionIoLimits.initialMessageId)).getOrThrow();
        expect(receipt.state, ActionIoDeliveryState.written);
        expect(receipt.confirmedBytes, bytes.length);
        expect(queue.runningCount, 0);
        final duplicate = (await input.claim(intent, io: config)).getOrThrow();
        expect(duplicate.created, isFalse);
        final replay = await launcher.execute(
          intent,
          claim: duplicate,
          credential: 'fixture',
          deadline: DateTime.now().add(const Duration(seconds: 20)),
        );
        expect((replay.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_REPLAY_FORBIDDEN');
        expect(await db.select(db.actionIoSessions).get(), hasLength(1));
      } finally {
        final shutdown = await supervisor.shutdown();
        if (scenario == 'success' || scenario == 'revoked_after_starting') {
          shutdown.getOrThrow();
        } else {
          expect(shutdown.isError(), isTrue);
        }
        await db.close();
        await directory.delete(recursive: true);
      }
    }, skip: !Platform.isWindows);
  }
}
