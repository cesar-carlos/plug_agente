import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/application/actions/action_io_remote_access.dart';
import 'package:plug_agente/application/rpc/action_io_rpc_handler.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/protocol/action_io_capability.dart';
import 'package:plug_agente/domain/protocol/action_io_rpc_call_context.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:plug_agente/infrastructure/validation/action_io_rpc_contract.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:result_dart/result_dart.dart';

class _Tokens extends Mock implements IClientTokenRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransportSchemaLoader loader;
  late ActionIoRpcContract contract;
  late ActionIoJournalDatabase db;
  late ActionIoOutputJournal output;
  late ActionIoRemoteAccess access;
  late _Tokens tokens;
  setUpAll(() async {
    loader = TransportSchemaLoader();
    await loader.loadAll();
    contract = ActionIoRpcContract(JsonSchemaContractValidator(loader: loader));
  });
  test('run and validateRun accept the same strict optional I/O configuration', () {
    for (final method in ['agent.action.run', 'agent.action.validateRun']) {
      final legacy = <String, dynamic>{'action_id': 'saved', 'idempotency_key': 'key'};
      expect(contract.validateParams(method, legacy).isSuccess(), isTrue);
      final io = <String, dynamic>{'version': 1, 'mode': 'faithful', 'close_input': true};
      expect(contract.validateParams(method, {...legacy, 'io': io}).isSuccess(), isTrue);
      expect(
        contract.validateParams(method, {
          ...legacy,
          'io': {...io, 'command': 'forbidden'},
        }).isError(),
        isTrue,
      );
      expect(
        contract.validateParams(method, {
          ...legacy,
          'io': {...io, 'version': 2},
        }).isError(),
        isTrue,
      );
    }
  });
  setUp(() async {
    db = ActionIoJournalDatabase(NativeDatabase.memory());
    final cipher = ActionIoPayloadCipher(keyId: 'key', key: SecretKey(List.filled(32, 7)));
    final input = DriftActionIoJournal(db, cipher);
    output = ActionIoOutputJournal(db, cipher);
    tokens = _Tokens();
    when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer(
      (_) async => Success(
        ClientTokenSummary(
          id: 'token',
          clientId: 'client',
          agentId: 'agent',
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
    access = ActionIoRemoteAccess(
      installationId: 'installation',
      authorization: ActionIoAuthorization(tokens),
      input: input,
      output: output,
      sessions: input,
    );
    (await input.claim(
      const ActionIoSessionIntent(
        executionId: 'e',
        installationId: 'installation',
        agentId: 'agent',
        clientId: 'client',
        actionId: 'action',
        idempotencyKey: 'key',
        fingerprint: 'f',
        triggerId: 't',
        definitionHash: 'h',
        actionType: 'executable',
      ),
    )).getOrThrow();
  });
  tearDown(() => db.close());
  Future<RpcResponse> call(
    String suffix,
    Map<String, dynamic> params, {
    bool enabled = true,
    bool negotiated = true,
    bool batch = false,
    Object? id = 1,
    String? credential = 'credential',
    bool Function()? isCancelled,
    TransportLimits limits = const TransportLimits(),
  }) {
    final method = 'agent.action.$suffix';
    return ActionIoRpcHandler(method, access: access, contract: contract, enabled: () => enabled).handle(
      RpcRequest(jsonrpc: '2.0', method: method, id: id, params: params),
      RpcDispatchContext(
        agentId: 'agent',
        clientToken: credential,
        streamEmitter: null,
        limits: limits,
        negotiatedExtensions: negotiated
            ? {
                'agentActions': {'io': ActionIoCapability.advertisement},
              }
            : {},
        actionIo: ActionIoRpcCallContext(
          connectionId: 'connection',
          deadline: DateTime.now().add(const Duration(seconds: 30)),
          isBatch: batch,
          isCancelled: isCancelled ?? () => false,
        ),
      ),
    );
  }

  for (final suffix in ['sendInput', 'closeInput', 'cancel']) {
    test('$suffix abandoned during authorization does not mutate the journal', () async {
      final policy = await tokens.getTokenPolicySummaryByHash('fixture');
      var cancelled = false;
      when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async {
        cancelled = true;
        return policy;
      });
      final response = await call(
        suffix,
        {
          'execution_id': 'e',
          if (suffix != 'cancel') ...{
            'message_id': 'late',
            'sequence': 0,
            if (suffix == 'sendInput') 'data_base64': 'AA==',
          },
        },
        isCancelled: () => cancelled,
      );
      expect(response.error, isNotNull);
      expect((response.error!.data as Map<String, dynamic>)['failure_code'], 'ACTION_IO_REQUEST_EXPIRED');
      expect(await db.select(db.actionIoMessages).get(), isEmpty);
      expect((await db.select(db.actionIoSessions).getSingle()).processState, 'queued');
    });
  }

  test('cancel commits queued completion and rejects batches before mutation', () async {
    expect((await call('cancel', {'execution_id': 'e'}, batch: true)).error, isNotNull);
    final queued = await call('getExecution', {'execution_id': 'e'});
    expect((queued.result as Map<String, dynamic>)['status'], 'queued');
    final cancelled = await call('cancel', {'execution_id': 'e'});
    expect(cancelled.error, isNull);
    final result = cancelled.result as Map<String, dynamic>;
    expect(result['cancelled'], isTrue);
    expect(result['reason'], 'cancelled');
    expect(result['status'], 'cancelled');
    expect(contract.validateResult('agent.action.cancel', result).isSuccess(), isTrue);
    expect((await call('cancel', {'execution_id': 'e'})).error, isNull);
  });

  test('getExecution returns journal metadata through the method-specific legacy schema', () async {
    final queued = await call('getExecution', {'execution_id': 'e'});
    expect(queued.error, isNull);
    final metadata = queued.result as Map<String, dynamic>;
    expect(metadata['status'], 'queued');
    expect(metadata['action_type'], 'executable');
    expect(metadata['definition_snapshot_hash'], 'h');
    expect(contract.validateResult('agent.action.getExecution', metadata).isSuccess(), isTrue);
    final streams = metadata['output'] as Map<String, dynamic>;
    expect((streams['stdout'] as Map<String, dynamic>)['captured'], isFalse);
    (await output.finish('e', exitCode: 0, complete: false, failureCode: 'ACTION_IO_CAPTURE_FAILED')).getOrThrow();
    final finished = await call('getExecution', {'execution_id': 'e', 'include_output': true});
    expect(finished.error, isNull);
    expect((finished.result as Map<String, dynamic>)['status'], 'failed');
    expect((await call('getExecution', {'execution_id': 'e'}, negotiated: false)).error, isNotNull);
  });

  Map<String, dynamic> message({String bytes = '', int sequence = 0}) => {
    'execution_id': 'e',
    'message_id': 'm$sequence',
    'sequence': sequence,
    'data_base64': bytes,
  };
  Map<String, dynamic> readParams() => {'execution_id': 'e', 'after_sequence': 0, 'max_bytes': 65536, 'wait_ms': 0};

  test('capability matches the canonical schema and incompatible peers do not negotiate', () {
    expect(
      loader.get(TransportSchemaIds.actionIoCapability)!.validate(ActionIoCapability.advertisement).isValid,
      isTrue,
    );
    expect(ActionIoCapability.negotiate(ActionIoCapability.advertisement, {'version': 1}), isNull);
    expect(ActionIoCapability.supported({...ActionIoCapability.advertisement, 'version': 1.0}), isFalse);
    expect(ActionIoCapability.negotiate(ActionIoCapability.advertisement, ActionIoCapability.advertisement), isNotNull);
  });

  test('faithful validation preserves legacy result fields without resolving stream access', () async {
    var validations = 0;
    final handler = ActionIoRpcHandler(
      'agent.action.validateRun',
      contract: contract,
      enabled: () => true,
      validateRun: (_, _) async {
        validations++;
        return {
          'valid': true,
          'action_id': 'saved',
          'action_type': 'executable',
          'would_replay_existing_execution': true,
          'existing_execution_id': 'original',
        };
      },
    );
    final response = await handler.handle(
      const RpcRequest(
        jsonrpc: '2.0',
        id: 1,
        method: 'agent.action.validateRun',
        params: {
          'action_id': 'saved',
          'idempotency_key': 'key',
          'io': {'version': 1, 'mode': 'faithful', 'close_input': true},
        },
      ),
      RpcDispatchContext(
        agentId: 'agent',
        clientToken: 'credential',
        streamEmitter: null,
        limits: const TransportLimits(),
        negotiatedExtensions: {
          'agentActions': {'io': ActionIoCapability.advertisement},
        },
        actionIo: ActionIoRpcCallContext(
          connectionId: 'connection',
          deadline: DateTime.now().add(const Duration(seconds: 30)),
          isBatch: false,
          isCancelled: () => false,
        ),
      ),
    );
    expect(response.isSuccess, isTrue);
    expect(validations, 1);
    expect((response.result as Map<String, dynamic>)['existing_execution_id'], 'original');
    expect(await db.select(db.actionIoMessages).get(), isEmpty);
  });

  test('local capability refusals describe the cause before accessing the token or journal', () async {
    for (final enabled in [false, true]) {
      final response = await call('sendInput', message(), enabled: enabled, negotiated: false);
      final data = response.error!.data as Map<String, dynamic>;
      expect(data['failure_code'], 'CAPABILITY_UNAVAILABLE');
      expect(data['reason'], enabled ? 'incompatible' : 'disabled');
      expect(data['user_message'], contains(enabled ? 'negociou' : 'desativado'));
      expect(response.error!.message, data['user_message']);
      expect(data['origin'], 'agent');
      expect(data['phase'], 'preflight');
      expect(data['effects_possible'], false);
      expect(data['outcome_unknown'], false);
      expect(data['retryable'], false);
      verifyNever(() => tokens.getTokenPolicySummaryByHash(any()));
    }
  });
  test('disabled absent negotiation notifications and mutating batches never admit input', () async {
    for (final response in [
      await call('sendInput', message(), enabled: false),
      await call('sendInput', message(), negotiated: false),
      await call('sendInput', message(), id: null),
      await call('sendInput', message(), batch: true),
    ]) {
      expect(response.error, isNotNull);
    }
    expect(await db.select(db.actionIoMessages).get(), isEmpty);
    verifyNever(() => tokens.getTokenPolicySummaryByHash(any()));
  });

  test('send duplicate status and ordered close preserve their method-specific receipts', () async {
    final sent = await call('sendInput', message(bytes: base64Encode([0, 13, 10, 26, 255, 128])));
    expect(sent.error, isNull);
    expect((sent.result as Map<String, dynamic>)['state'], 'accepted');
    expect((await call('sendInput', message(bytes: base64Encode([0, 13, 10, 26, 255, 128])))).result, sent.result);
    final closed = await call('closeInput', {'execution_id': 'e', 'message_id': 'close', 'sequence': 1});
    expect(closed.error, isNull);
    expect((closed.result as Map<String, dynamic>)['stdin_state'], 'closing');
    final status = await call('getInputStatus', {'execution_id': 'e', 'message_id': 'close'});
    expect(status.result, closed.result);
    expect((await call('sendInput', message(sequence: 2))).error, isNotNull);
    expect(await db.select(db.actionIoMessages).get(), hasLength(2));
  });

  test('noncanonical base64 and conflicting credential aliases are refused', () async {
    expect((await call('sendInput', message(bytes: '/x=='))).error, isNotNull);
    final denied = await call('sendInput', {...message(), 'client_token': 'other'});
    expect(denied.error!.code, RpcErrorCode.unauthorized);
    expect(await db.select(db.actionIoMessages).get(), isEmpty);
  });

  test('find resolves owner scope and read returns original binary bytes with incomplete terminal metadata', () async {
    expect((await call('findExecution', {'action_id': 'action', 'idempotency_key': 'key'})).result, {
      'found': true,
      'execution_id': 'e',
    });
    expect((await call('findExecution', {'action_id': 'action', 'idempotency_key': 'missing'})).result, {
      'found': false,
      'execution_id': null,
      'reason': 'not_found_in_retention_window',
    });
    (await output.append('e', ActionIoStream.stderr, [0, 255, 128])).getOrThrow();
    (await output.finish('e', exitCode: 0, complete: false, failureCode: 'ACTION_IO_CAPTURE_FAILED')).getOrThrow();
    final response = await call('readIo', readParams());
    expect(response.error, isNull);
    final result = response.result as Map<String, dynamic>;
    final events = (result['events'] as List).cast<Map<String, dynamic>>();
    expect(result['output_complete'], isFalse);
    expect(base64Decode(events[0]['data_base64'] as String), [0, 255, 128]);
    expect((events[2]['failure'] as Map<String, dynamic>)['retryable'], isFalse);
    expect((await call('readIo', {...readParams(), 'wait_ms': 1}, batch: true)).error, isNotNull);
    expect((await call('readIo', readParams(), limits: const TransportLimits(maxPayloadBytes: 1))).error, isNotNull);
  });
}
