import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_environment_resolver.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_admission.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/application/actions/action_io_catalog.dart';
import 'package:plug_agente/application/actions/action_io_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_intent_preparer.dart';
import 'package:plug_agente/application/actions/action_io_local_intent_validator.dart';
import 'package:plug_agente/application/actions/action_io_remote_access.dart';
import 'package:plug_agente/application/actions/action_io_session_launcher.dart';
import 'package:plug_agente/application/actions/action_io_session_supervisor.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_execution_gate_chain.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/application/rpc/action_io_rpc_handler.dart';
import 'package:plug_agente/application/rpc/action_io_run.dart';
import 'package:plug_agente/application/rpc/action_io_validate_run.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/protocol/action_io_capability.dart';
import 'package:plug_agente/domain/protocol/action_io_rpc_call_context.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_action_io_invocation_resolver.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process_factory.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/infrastructure/actions/action_io_invocation_resolver.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/executable_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_io_process_factory.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_job_api.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_repository.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart' hide ActionIoEvent;
import 'package:plug_agente/infrastructure/stores/action_io_journal_runtime.dart';
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:plug_agente/infrastructure/stores/action_io_secure_key_store.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:plug_agente/infrastructure/validation/action_io_rpc_contract.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/action_io_credential_fixture.dart';
import '../../helpers/action_io_hub_blocked_input.dart';
import '../../helpers/action_io_hub_cancellation.dart';
import '../../helpers/action_io_hub_fixture.dart';
import '../../helpers/action_io_hub_ownership.dart';
import '../../helpers/action_io_hub_revocation.dart';
import '../../helpers/action_io_hub_rotation.dart';
import '../../helpers/action_io_hub_shutdown.dart';
import '../../helpers/action_io_runtime_recovery.dart';
import '../../helpers/action_io_saved_approval.dart';
import '../../helpers/e2e_env.dart';

class _Dispatch extends Mock implements DispatchAgentActionTrigger {}

class _Secrets extends Mock implements IAgentActionSecretStore {}

class _Runner extends Mock implements AgentActionLocalRunner {}

class _Tokens extends Mock implements IClientTokenRepository {}

class _ObservedProcesses implements IActionIoProcessFactory {
  _ObservedProcesses(this.delegate);
  final IActionIoProcessFactory delegate;
  Future<void> Function()? beforeStart;
  Future<void> Function()? afterStart;
  int starts = 0;
  @override
  Future<Result<IActionIoProcess>> start(ActionIoInvocation invocation) async {
    starts++;
    await beforeStart?.call();
    final result = await delegate.start(invocation);
    if (result.isSuccess()) await afterStart?.call();
    return result;
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.environment.containsKey('ACTION_IO_HUB_MANIFEST')) {
    // Explicit private fixture: never load the checkout's operational .env.
    await E2EEnv.loadForTesting('');
    await E2EEnv.load();
    HttpOverrides.global = null;
  }
  setUpAll(
    () => registerFallbackValue(
      const AgentActionExecutionRequest(actionId: 'a', source: AgentActionRequestSource.remoteHub),
    ),
  );
  test('RPC run admits asynchronously, delivers bytes and returns terminal duplicates', () async {
    final hub = ActionIoHubFixture.fromEnvironment();
    final agentId = hub?.agentId ?? 'a';
    final clientId = hub?.clientId ?? 'c';
    const snapshotter = AgentActionDefinitionSnapshotter();
    final directory = await Directory.systemTemp.createTemp('action-io-launcher-');
    final actionDatabase = AppDatabase(executor: NativeDatabase(File('${directory.path}/actions.sqlite')));
    final repository = AgentActionRepository(actionDatabase);
    final runner = _Runner();
    when(() => runner.type).thenReturn(AgentActionType.executable);
    final gates = AgentActionExecutionGateChain(
      repository: repository,
      runnerRegistry: AgentActionLocalRunnerRegistry([runner]),
      definitionSnapshotter: snapshotter,
      secretReferenceFingerprinter: AgentActionSecretReferenceFingerprinter(_Secrets()),
    );
    final queue = ActionExecutionQueue();
    final invocations = ActionIoInvocationResolver(
      AgentActionAdapterRegistry([ExecutableActionAdapter()]),
      const ActionEnvironmentResolver(),
      const AgentOperationalProfileResolver(),
    );
    var definition = AgentActionDefinition(
      id: 'action',
      name: 'Saved',
      state: AgentActionState.active,
      config: ExecutableActionConfig(
        executablePath: AgentActionPathReference(
          originalPath: '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
        ),
        arguments: const [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'$i=[Console]::OpenStandardInput();$o=[Console]::OpenStandardOutput();$e=[Console]::OpenStandardError();$b=New-Object byte[] 65536;while(($n=$i.Read($b,0,$b.Length)) -gt 0){$o.Write($b,0,$n);$o.Flush();$e.Write($b,0,$n);$e.Flush()}',
        ],
      ),
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
    definition = (await repository.saveDefinition(definition)).getOrThrow();
    (await repository.saveTrigger(trigger)).getOrThrow();
    expect((await repository.getDefinition('action')).getOrThrow().policies.remote.allowFaithfulIo, isTrue);
    expect(
      (await repository.getDefinition('action')).getOrThrow().policies.remote.riskFingerprint,
      snapshotter.riskFingerprint(definition),
    );
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
      agentId: agentId,
      clientId: clientId,
      actionId: 'action',
      idempotencyKey: 'key',
      fingerprint: 'request',
      triggerId: 'trigger',
      definitionHash: snapshotter.snapshotHash(definition),
      actionType: definition.type.name,
    );
    final db = ActionIoJournalDatabase(NativeDatabase(File('${directory.path}/journal.sqlite')));
    final cipher = ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 7)));
    late final DriftActionIoJournal input;
    late final ActionIoOutputJournal output;
    final metrics = MetricsCollector();
    final fixtureKey = 'fixture_action_io_${directory.uri.pathSegments.where((part) => part.isNotEmpty).last}';
    final runtime = hub == null
        ? null
        : ActionIoJournalRuntime(
            '${directory.path}/journal.sqlite',
            metrics: metrics.actionIoMetrics,
            keyStore: ActionIoSecureKeyStore(
              lockPath: '${directory.path}/journal.sqlite.key.lock',
              keyName: fixtureKey,
            ),
          );
    final supervisor = ActionIoSessionSupervisor(metrics: metrics.actionIoMetrics);
    ActionIoCredentialFixture? credentials;
    ({String executionId, List<int> bytes})? recovery;
    try {
      if (hub != null) {
        credentials = ActionIoCredentialFixture(directory);
        (await runtime!.prepare(enabled: true)).getOrThrow();
      }
      input = runtime?.journal ?? DriftActionIoJournal(db, cipher, metrics: metrics.actionIoMetrics);
      output = runtime?.output ?? ActionIoOutputJournal(db, cipher, metrics: metrics.actionIoMetrics);
      final tokenStub = _Tokens();
      when(() => tokenStub.getTokenPolicySummaryByHash(any())).thenAnswer(
        (_) async => Success(
          ClientTokenSummary(
            id: 'token',
            clientId: clientId,
            agentId: agentId,
            createdAt: DateTime.utc(2026),
            isRevoked: false,
            allTables: false,
            allViews: false,
            rules: const [],
            payload: const {
              'agent_action_scopes': ['agent_actions.*'],
            },
          ),
        ),
      );
      IClientTokenRepository tokens = tokenStub;
      String? provisionedTokenId;
      if (hub != null) {
        final provisioned = await credentials!.provision(clientId, agentId);
        tokens = credentials.repository;
        hub.credential = provisioned.tokenValue;
        provisionedTokenId = provisioned.tokenId;
      }
      final bytes = List.generate(65536, (i) => i % 256);
      final interactive = hub == null ? <int>[] : <int>[0, 13, 10, 26, 255, 128, 65];
      final expectedBytes = [...bytes, ...interactive];
      final config = ActionIoConfiguration(initialInput: bytes, closeInput: hub == null);

      final processes = _ObservedProcesses(
        WindowsActionIoProcessFactory(WindowsJobObjectProcessTreeController(api: WindowsActionJobApi())),
      );
      final spawnCrash = Platform.environment['ACTION_IO_CRASH_SPAWN'];
      if (hub != null && (spawnCrash == 'before' || spawnCrash == 'after')) {
        Future<void> interruptSpawn() async {
          final lookup = (await input.findExecution(
            installationId: 'i',
            agentId: agentId,
            clientId: clientId,
            actionId: intent.actionId,
            idempotencyKey: 'key',
          )).getOrThrow();
          final id = lookup.session!.executionId;
          expect((await input.getExecutionSnapshot(id)).getOrThrow().processState, 'starting');
          await File('${hub.fixtureRoot}/crash-checkpoint.json').writeAsString(
            jsonEncode({
              'format': 'action-io-crash-v1',
              'kind': 'native-starting',
              'boundary': spawnCrash,
              'directory': directory.path,
              'keyName': fixtureKey,
              'executionId': id,
              'clientId': clientId,
            }),
            flush: true,
          );
          exit(73);
        }

        if (spawnCrash == 'before') {
          processes.beforeStart = interruptSpawn;
        } else {
          processes.afterStart = interruptSpawn;
        }
      }
      final launcher = ActionIoSessionLauncher(
        authorization: ActionIoAuthorization(tokens),
        validator: validator,
        repository: repository,
        invocations: invocations,
        processes: processes,
        input: input,
        output: output,
        queue: ActionIoExecutionQueue(queue, supervisor, metrics: metrics.actionIoMetrics),
      );
      final triggers = RunAgentActionViaRemoteTrigger(repository, _Dispatch());
      final authorization = ActionIoAuthorization(tokens);
      final expiredRunCompleted = Completer<void>();
      String? expiredRunCode;
      final run = ActionIoRun(
        preparer: ActionIoIntentPreparer(
          installationId: 'i',
          authorization: authorization,
          sessions: input,
          repository: repository,
          triggers: triggers,
        ),
        admission: ActionIoAdmission(
          authorization: authorization,
          journal: input,
          sessions: input,
          accepting: () => supervisor.accepting,
          validateLocalIntent: (candidate) async {
            if (candidate.idempotencyKey == 'live-expired-admission') {
              await Future<void>.delayed(const Duration(milliseconds: 1500));
            }
            return validator.validate(candidate);
          },
        ),
        launcher: launcher,
        supervisor: supervisor,
        sessions: input,
        authorization: authorization,
      );
      final request = RpcRequest(
        jsonrpc: '2.0',
        method: 'agent.action.run',
        id: 'run',
        params: {
          'action_id': intent.actionId,
          'idempotency_key': intent.idempotencyKey,
          'io': {
            'version': 1,
            'mode': 'faithful',
            'close_input': config.closeInput,
            'initial_input_base64': base64Encode(bytes),
          },
        },
      );
      final context = RpcDispatchContext(
        agentId: agentId,
        clientToken: hub?.credential ?? 'fixture',
        streamEmitter: null,
        limits: const TransportLimits(),
        negotiatedExtensions: const {
          'agentActions': {'io': ActionIoCapability.advertisement},
        },
        actionIo: ActionIoRpcCallContext(
          connectionId: 'fixture',
          deadline: DateTime.now().add(const Duration(seconds: 30)),
          isBatch: false,
          isCancelled: () => false,
        ),
      );
      final loader = TransportSchemaLoader();
      await loader.loadAll();
      final handler = ActionIoRpcHandler(
        'agent.action.run',
        contract: ActionIoRpcContract(JsonSchemaContractValidator(loader: loader)),
        enabled: () => true,
        run: (request, context) async {
          try {
            return await run.call(request, context);
          } on ActionFailure catch (error) {
            if (request.id == 'live-expired-admission') expiredRunCode = error.code;
            rethrow;
          } finally {
            if (request.id == 'live-expired-admission') expiredRunCompleted.complete();
          }
        },
      );
      if (hub != null) {
        final second = definition.copyWith(id: 'action-second', name: 'Second catalog action',
          config: ExecutableActionConfig(
            executablePath: (definition.config as ExecutableActionConfig).executablePath,
            arguments: ['-NoProfile', '-NonInteractive', '-File', File('tool/homologation/action_io_echo.ps1').absolute.path],
          ),
          policies: definition.policies.copyWith(remote: definition.policies.remote.copyWith(
            stdinDescription: 'Arbitrary bytes until EOF', stdoutDescription: 'Exact echo', stderrDescription: 'EOF line',
          )),
        );
        final signed = second.copyWith(policies: second.policies.copyWith(
          remote: second.policies.remote.copyWith(riskFingerprint: snapshotter.riskFingerprint(second)),
        ));
        (await repository.saveDefinition(signed)).getOrThrow();
        (await repository.saveTrigger(const AgentActionTrigger(
          id: 'second-trigger', actionId: 'action-second', type: AgentActionTriggerType.remote,
        ))).getOrThrow();
        await hub.connect(
          run: handler,
          catalog: ActionIoCatalog(repository, authorization, (action) async => action.canRun && action.policies.remote.canRunSavedAction && action.policies.remote.allowFaithfulIo),
          validate: ActionIoRpcHandler(
            'agent.action.validateRun',
            contract: ActionIoRpcContract(JsonSchemaContractValidator(loader: loader)),
            enabled: () => true,
            validateRun: ActionIoValidateRun(run.preparer, run.admission).call,
          ),
          contract: ActionIoRpcContract(JsonSchemaContractValidator(loader: loader)),
          access: ActionIoRemoteAccess(
            metrics: metrics.actionIoMetrics,
            installationId: 'i',
            authorization: authorization,
            input: input,
            output: output,
            sessions: input,
            requestCancel: supervisor.requestCancel,
          ),
        );
      }
      Future<RpcResponse> dispatch(RpcRequest request) => hub?.call(request) ?? handler.handle(request, context);
      if (hub != null) {
        final startsBeforeExpiry = processes.starts;
        try {
          final expired = await hub.call(
            RpcRequest(
              jsonrpc: '2.0',
              id: 'live-expired-admission',
              method: request.method,
              params: {...request.params! as Map<String, dynamic>, 'idempotency_key': 'live-expired-admission'},
            ),
            timeoutMs: 500,
          );
          expect(expired.error, isNotNull);
        } on Object catch (error) {
          // The hub may report its elapsed request before the late agent reply.
          expect(error, isA<StateError>());
        }
        await expiredRunCompleted.future.timeout(const Duration(seconds: 10));
        expect(expiredRunCode, 'ACTION_IO_REQUEST_EXPIRED');
        expect(processes.starts, startsBeforeExpiry);
        expect(
          (await input.findExecution(
            installationId: 'i',
            agentId: agentId,
            clientId: clientId,
            actionId: intent.actionId,
            idempotencyKey: 'live-expired-admission',
          )).getOrThrow().session,
          isNull,
        );
      }
      if (hub != null) {
        const delayedKey = 'live-transit-expiry';
        final observed = hub.observeRun(delayedKey);
        await File('${hub.fixtureRoot}/delay-next-rpc').writeAsString('', flush: true);
        final startsBeforeTransit = processes.starts;
        try {
          final delayed = await hub.call(
            RpcRequest(
              jsonrpc: '2.0',
              id: delayedKey,
              method: request.method,
              params: {...request.params! as Map<String, dynamic>, 'idempotency_key': delayedKey},
            ),
            timeoutMs: 500,
          );
          expect(delayed.error, isNotNull);
        } on Object catch (error) {
          expect(error, isA<StateError>());
        }
        final lateResponse = await observed.timeout(const Duration(seconds: 10));
        expect(lateResponse.error, isNotNull);
        expect((lateResponse.error!.data as Map)['failure_code'], 'ACTION_IO_REQUEST_EXPIRED');
        expect(processes.starts, startsBeforeTransit);
        expect(
          (await input.findExecution(
            installationId: 'i',
            agentId: agentId,
            clientId: clientId,
            actionId: intent.actionId,
            idempotencyKey: delayedKey,
          )).getOrThrow().session,
          isNull,
        );
        expect(File('${hub.fixtureRoot}/delay-next-rpc').existsSync(), isFalse);
      }
      final response = await dispatch(request);
      expect(response.error, isNull, reason: '${response.error?.code}: ${response.error?.message}');
      final admitted = response.result as Map<String, dynamic>;
      final executionId = admitted['execution_id'] as String;
      expect((admitted['io'] as Map)['initial_message_id'], ActionIoLimits.initialMessageId);
      if (hub == null) {
        expect((admitted['io'] as Map)['close_message_id'], ActionIoLimits.closeMessageId);
      } else {
        Future<RpcResponse>? waitingRead;
        var readCompleted = false;
        for (final message in [('empty', 1, <int>[]), ('interactive', 2, interactive)]) {
          final sent = await hub.call(
            RpcRequest(
              jsonrpc: '2.0',
              id: message.$1,
              method: 'agent.action.sendInput',
              params: {
                'execution_id': executionId,
                'message_id': message.$1,
                'sequence': message.$2,
                'data_base64': base64Encode(message.$3),
              },
            ),
          );
          expect(sent.error, isNull, reason: '${sent.error?.code}: ${sent.error?.message}');
          if (message.$1 == 'empty') {
            await hub.reconnectCaller();
            var cursor = 0;
            var initialBytes = 0;
            for (var attempt = 0; initialBytes < bytes.length * 2 && attempt < 20; attempt++) {
              final initial = await hub.call(
                RpcRequest(
                  jsonrpc: '2.0',
                  id: 'initial-$attempt',
                  method: 'agent.action.readIo',
                  params: {
                    'execution_id': executionId,
                    'after_sequence': cursor,
                    'max_bytes': ActionIoLimits.pageBytes,
                    'wait_ms': 1000,
                  },
                ),
              );
              expect(initial.error, isNull);
              final result = initial.result as Map<String, dynamic>;
              cursor = result['next_sequence'] as int;
              for (final event in (result['events'] as List).cast<Map<String, dynamic>>()) {
                if (event['type'] == 'output') initialBytes += base64Decode(event['data_base64'] as String).length;
              }
            }
            expect(initialBytes, bytes.length * 2);
            supervisor.pauseForMaintenance('private-live-maintenance').getOrThrow();
            try {
              final startsBeforePause = processes.starts;
              final refused = await hub.call(
                RpcRequest(
                  jsonrpc: '2.0',
                  id: 'maintenance-run',
                  method: request.method,
                  params: {
                    ...request.params! as Map<String, dynamic>,
                    'idempotency_key': 'maintenance-refused',
                  },
                ),
              );
              expect(refused.error, isNotNull);
              expect((refused.error!.data as Map)['failure_code'], 'ACTION_IO_ADMISSION_CLOSED');
              expect(processes.starts, startsBeforePause);
              expect(
                (await input.findExecution(
                  installationId: 'i',
                  agentId: agentId,
                  clientId: clientId,
                  actionId: intent.actionId,
                  idempotencyKey: 'maintenance-refused',
                )).getOrThrow().session,
                isNull,
              );
              expect((await input.getExecutionSnapshot(executionId)).getOrThrow().processState, 'running');
            } finally {
              supervisor.resumeAfterMaintenance('private-live-maintenance').getOrThrow();
            }
            if (Platform.environment['ACTION_IO_CRASH'] == 'true') {
              // Additional committed intent has no launcher or pipe owner.
              // Abrupt exit must never promote its admitted bytes to delivery.
              for (final checkpointId in ['crash-queued', 'crash-writing']) {
                (await input.claim(
                  ActionIoSessionIntent(
                    executionId: checkpointId,
                    installationId: intent.installationId,
                    agentId: agentId,
                    clientId: clientId,
                    actionId: intent.actionId,
                    idempotencyKey: checkpointId,
                    fingerprint: intent.fingerprint,
                    triggerId: intent.triggerId,
                    definitionHash: intent.definitionHash,
                  ),
                )).getOrThrow();
                final queuedReceipt = (await input.admitInput(
                  executionId: checkpointId,
                  clientId: clientId,
                  messageId: 'pending',
                  sequence: 0,
                  bytes: [0, 255, 26],
                )).getOrThrow();
                expect(queuedReceipt.state, ActionIoDeliveryState.accepted);
                if (checkpointId == 'crash-writing') {
                  (await input.markStarting(checkpointId)).getOrThrow();
                  (await input.markRunning(checkpointId)).getOrThrow();
                  final claimed = (await input.beginNextInput(checkpointId)).getOrThrow().input!;
                  expect(claimed.receipt.state, ActionIoDeliveryState.writing);
                  expect(claimed.bytes, [0, 255, 26]);
                }
              }
              expect((await input.getExecutionSnapshot(executionId)).getOrThrow().processState, 'running');
              expect(
                (await input.inputStatus(executionId, clientId, ActionIoLimits.initialMessageId)).getOrThrow().state,
                ActionIoDeliveryState.written,
              );
              await File('${hub.fixtureRoot}/crash-checkpoint.json').writeAsString(
                jsonEncode({
                  'format': 'action-io-crash-v1',
                  'directory': directory.path,
                  'keyName': fixtureKey,
                  'executionId': executionId,
                  'clientId': clientId,
                  'queuedExecutionId': 'crash-queued',
                  'writingExecutionId': 'crash-writing',
                }),
                flush: true,
              );
              // Deliberately bypass finally: this isolated test process owns all handles.
              exit(73);
            }
            waitingRead = hub
                .call(
                  RpcRequest(
                    jsonrpc: '2.0',
                    id: 'waiting-read',
                    method: 'agent.action.readIo',
                    params: {
                      'execution_id': executionId,
                      'after_sequence': cursor,
                      'max_bytes': ActionIoLimits.pageBytes,
                      'wait_ms': 20000,
                    },
                  ),
                )
                .whenComplete(() => readCompleted = true);
            await Future<void>.delayed(const Duration(milliseconds: 150));
            expect(readCompleted, isFalse, reason: 'Reader must actually wait before interactive input.');
          } else {
            final resumed = await waitingRead!.timeout(const Duration(seconds: 5));
            expect(resumed.error, isNull);
            expect((resumed.result as Map)['events'], isNotEmpty);
          }
        }
        final closed = await hub.call(
          RpcRequest(
            jsonrpc: '2.0',
            id: 'close',
            method: 'agent.action.closeInput',
            params: {'execution_id': executionId, 'message_id': 'explicit-close', 'sequence': 3},
          ),
        );
        expect(closed.error, isNull);
      }
      final limit = DateTime.now().add(const Duration(seconds: 20));
      while (!supervisor.isSafelyIdle && DateTime.now().isBefore(limit)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(supervisor.isSafelyIdle, isTrue);
      final row = await db.select(db.actionIoSessions).getSingle();
      expect(row.processState, 'finished');
      expect(row.actionType, definition.type.name);
      expect((await input.getSessionReference(executionId)).getOrThrow().actionType, definition.type.name);
      final page = (await output.read(
        executionId: executionId,
        clientId: clientId,
        afterSequence: 0,
        maxBytes: ActionIoLimits.pageBytes,
      )).getOrThrow();
      for (final stream in ActionIoStream.values) {
        final events = page.events.whereType<ActionIoOutputEvent>().where((event) => event.stream == stream).toList();
        expect(
          events.expand((event) => event.bytes).toList(),
          expectedBytes,
          reason: '${stream.name} must preserve every byte',
        );
        var offset = 0;
        for (final event in events) {
          expect(event.offset, offset, reason: '${stream.name} offsets must be contiguous');
          offset += event.bytes.length;
        }
      }
      if (hub != null) {
        final events = <Map<String, dynamic>>[];
        var cursor = 0;
        var completed = false;
        var pages = 0;
        while (!completed && pages < 16) {
          final remote = await hub.call(
            RpcRequest(
              jsonrpc: '2.0',
              id: 'read-${pages++}',
              method: 'agent.action.readIo',
              params: {
                'execution_id': executionId,
                'after_sequence': cursor,
                'max_bytes': ActionIoLimits.blockBytes,
                'wait_ms': 0,
              },
            ),
          );
          expect(remote.error, isNull);
          final result = remote.result as Map<String, dynamic>;
          expect(result['terminal'], isTrue);
          expect(result['output_complete'], isTrue);
          final delivered = (result['events'] as List).cast<Map<String, dynamic>>();
          expect(delivered, isNotEmpty);
          for (final event in delivered) {
            expect(event['sequence'], ++cursor);
            completed = completed || event['type'] == 'completed';
          }
          expect(result['next_sequence'], cursor);
          events.addAll(delivered);
          if (pages == 1) await hub.reconnectCaller();
        }
        expect(completed, isTrue);
        expect(pages, greaterThan(1));
        for (final stream in ActionIoStream.values) {
          expect(
            events
                .where((event) => event['type'] == 'output' && event['stream'] == stream.name)
                .expand((event) => base64Decode(event['data_base64'] as String))
                .toList(),
            expectedBytes,
          );
        }
      }
      final receipt = (await input.inputStatus(executionId, clientId, ActionIoLimits.initialMessageId)).getOrThrow();
      expect(receipt.state, ActionIoDeliveryState.written);
      expect(receipt.confirmedBytes, bytes.length);
      final snapshot = (await input.getExecutionSnapshot(executionId)).getOrThrow();
      expect(snapshot.admittedInputBytes, expectedBytes.length);
      expect(snapshot.confirmedInputBytes, expectedBytes.length);
      expect(queue.runningCount, 0);
      final duplicateResponse = await dispatch(
        RpcRequest(jsonrpc: '2.0', method: request.method, id: 'duplicate', params: request.params),
      );
      expect(duplicateResponse.error, isNull);
      final duplicate = duplicateResponse.result as Map<String, dynamic>;
      expect(duplicate['execution_id'], executionId);
      expect(duplicate['status'], 'succeeded');
      final counters = metrics.getSnapshot();
      expect(counters[MetricsCounterNames.actionIoAdmittedInputBytes], expectedBytes.length);
      expect(counters[MetricsCounterNames.actionIoInputConfirmedBytes], expectedBytes.length);
      expect(counters[MetricsCounterNames.actionIoPersistedOutputBytes], expectedBytes.length * 2);
      expect(counters[MetricsCounterNames.actionIoInputWritten], hub == null ? 2 : 4);
      expect(counters[MetricsCounterNames.actionIoExecutionSucceeded], 1);
      expect(counters[MetricsCounterNames.actionIoCaptureComplete], 1);
      expect(counters[MetricsCounterNames.actionIoQueueWaiting], 0);
      expect(counters[MetricsCounterNames.actionIoSessionsOwned], 0);
      expect(counters[MetricsCounterNames.actionIoCleanupUnconfirmed], 0);
      await verifyActionIoSavedApproval(
        repository: repository,
        definition: definition,
        original: request,
        executionId: executionId,
        dispatch: dispatch,
      );
      recovery = (executionId: executionId, bytes: expectedBytes);
      expect(await db.select(db.actionIoSessions).get(), hasLength(1));
      if (hub != null) {
        final startsBeforeCancellation = processes.starts;
        await verifyActionIoQueuedCancellation(hub, queue, supervisor, intent.actionId);
        expect(processes.starts, startsBeforeCancellation);
      }
      if (hub != null) await hub.verifyReferenceClient(intent.actionId);
      if (hub != null) await verifyActionIoHubCancellation(hub, intent.actionId);
      if (hub != null) {
        await verifyActionIoHubBlockedInput(
          hub,
          repository,
          definition,
          onWriting: Platform.environment['ACTION_IO_CRASH_WRITE'] == 'true'
              ? (blockedId) async {
                  await File('${hub.fixtureRoot}/crash-checkpoint.json').writeAsString(
                    jsonEncode({
                      'format': 'action-io-crash-v1',
                      'kind': 'native-writing',
                      'directory': directory.path,
                      'keyName': fixtureKey,
                      'executionId': blockedId,
                      'clientId': clientId,
                    }),
                    flush: true,
                  );
                  exit(73);
                }
              : null,
        );
      }
      if (hub != null && credentials != null) {
        final ownerCredential = hub.credential;
        final probe = await credentials.provision('catalog-isolation-probe', hub.agentId);
        Future<RpcResponse> page(String id, [String? cursor]) => hub.call(RpcRequest(
          jsonrpc: '2.0', id: id, method: 'agent.action.listAvailable',
          params: {'page_size': 1, 'cursor': ?cursor},
        ));
        try {
          final first = await page('owner-catalog');
          final ownerCursor = (first.result as Map)['next_cursor'] as String;
          hub.credential = probe.tokenValue;
          final foreign = await page('foreign-cursor', ownerCursor);
          expect(foreign.error, isNotNull);
          expect((foreign.error!.data as Map)['failure_code'], 'ACTION_CATALOG_INVALID_CURSOR');
          expect(foreign.result, isNull);
          final permitted = await page('probe-catalog');
          final probeCursor = (permitted.result as Map)['next_cursor'] as String;
          (await credentials.repository.revokeToken(probe.tokenId)).getOrThrow();
          final revoked = await page('revoked-cursor', probeCursor);
          expect(revoked.error, isNotNull);
          expect((revoked.error!.data as Map)['failure_code'], 'ACTION_IO_UNAUTHORIZED');
          expect(revoked.result, isNull);
        } finally {
          hub.credential = ownerCredential;
        }
        await verifyActionIoHubOwnership(
          hub: hub,
          credentials: credentials,
          executionId: executionId,
          actionId: intent.actionId,
        );
        final sessionsBeforeRotation = (await db.select(db.actionIoSessions).get()).length;
        final messagesBeforeRotation = (await db.select(db.actionIoMessages).get()).length;
        await verifyActionIoHubRotation(
          hub: hub,
          actionId: intent.actionId,
          credentials: credentials,
          tokenId: provisionedTokenId!,
          executionId: executionId,
        );
        expect(await db.select(db.actionIoSessions).get(), hasLength(sessionsBeforeRotation));
        expect(await db.select(db.actionIoMessages).get(), hasLength(messagesBeforeRotation));
        await verifyActionIoHubRevocation(hub, intent.actionId, () async {
          (await credentials!.repository.revokeToken(provisionedTokenId!)).getOrThrow();
        });
        final deniedMessages = await (db.select(
          db.actionIoMessages,
        )..where((row) => row.messageId.equals('never-admitted'))).get();
        expect(deniedMessages, isEmpty);
        hub.credential = (await credentials.provision(clientId, agentId)).tokenValue;
        await verifyActionIoHubShutdown(
          hub: hub,
          actionId: intent.actionId,
          supervisor: supervisor,
          sessions: input,
        );
      }
    } finally {
      await hub?.close();
      (await supervisor.shutdown()).getOrThrow();
      await db.close();
      if (runtime != null) (await runtime.close()).getOrThrow();
      if (runtime != null && recovery != null) {
        await verifyActionIoRuntimeRecovery(runtime.path, fixtureKey, recovery.executionId, recovery.bytes);
      }
      await credentials?.database.close();
      await actionDatabase.close();
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);
}
