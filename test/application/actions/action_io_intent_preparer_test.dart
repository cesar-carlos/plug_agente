import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_io_admission.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/application/actions/action_io_intent_preparer.dart';
import 'package:plug_agente/application/rpc/action_io_validate_run.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_session_reference.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class _Journal extends Mock implements IActionIoJournal {}

class _Tokens extends Mock implements IClientTokenRepository {}

class _Sessions extends Mock implements IActionIoSessionLookup {}

class _Repository extends Mock implements IAgentActionRepository {}

class _Triggers extends Mock implements RunAgentActionViaRemoteTrigger {}

void main() {
  const revoked = false;
  const client = 'client';
  ClientTokenSummary token() => ClientTokenSummary(
    id: 'token',
    clientId: client,
    agentId: 'agent',
    createdAt: DateTime.utc(2026),
    isRevoked: revoked,
    allTables: false,
    allViews: false,
    rules: const [],
    payload: const {
      'agent_action_scopes': ['agent_actions.*'],
    },
  );

  test('duplicate preparation uses original snapshot without current action or trigger lookup', () async {
    final tokens = _Tokens();
    final sessions = _Sessions();
    final repository = _Repository();
    final triggers = _Triggers();
    when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(token()));
    when(
      () => sessions.findExecution(
        installationId: 'i',
        agentId: 'agent',
        clientId: 'client',
        actionId: 'action',
        idempotencyKey: 'key',
      ),
    ).thenAnswer(
      (_) async => const Success(
        ActionIoExecutionLookup(
          ActionIoSessionReference(
            executionId: 'original',
            installationId: 'i',
            agentId: 'agent',
            clientId: 'client',
            actionId: 'action',
            triggerId: 'old-trigger',
            definitionHash: 'old-definition',
            actionType: 'executable',
          ),
        ),
      ),
    );
    final preparer = ActionIoIntentPreparer(
      installationId: 'i',
      authorization: ActionIoAuthorization(tokens),
      sessions: sessions,
      repository: repository,
      triggers: triggers,
    );
    final run = (await preparer.prepare(
      agentId: 'agent',
      credential: 'token',
      actionId: 'action',
      idempotencyKey: 'key',
      validateOnly: false,
    )).getOrThrow();
    final validation = (await preparer.prepare(
      agentId: 'agent',
      credential: 'rotated',
      actionId: 'action',
      idempotencyKey: 'key',
      validateOnly: true,
    )).getOrThrow();
    expect(run.executionId, 'original');
    expect(run.definitionHash, 'old-definition');
    expect(run.actionType, 'executable');
    expect(validation.actionType, 'executable');
    expect(run.triggerId, 'old-trigger');
    expect(run.fingerprint, validation.fingerprint);
    final changed = (await preparer.prepare(
      agentId: 'agent',
      credential: 'token',
      actionId: 'action',
      idempotencyKey: 'key',
      triggerId: 'different',
      validateOnly: false,
    )).getOrThrow();
    expect(changed.fingerprint, isNot(run.fingerprint));

    registerFallbackValue(run);
    registerFallbackValue(ActionIoConfiguration(closeInput: true));
    when(() => sessions.previewClaim(any(), io: any(named: 'io'))).thenAnswer(
      (_) async => const Success(
        ActionIoExecutionLookup(
          ActionIoSessionReference(
            executionId: 'original',
            installationId: 'i',
            agentId: 'agent',
            clientId: 'client',
            actionId: 'action',
            actionType: 'executable',
            triggerId: 'old-trigger',
            definitionHash: 'old-definition',
          ),
        ),
      ),
    );
    final journal = _Journal();
    final validate = ActionIoValidateRun(
      preparer,
      ActionIoAdmission(
        authorization: ActionIoAuthorization(tokens),
        journal: journal,
        sessions: sessions,
        accepting: () => true,
        validateLocalIntent: (_) async => throw StateError('Duplicates must not use the current definition'),
      ),
    );
    final result = await validate.call(
      const RpcRequest(
        jsonrpc: '2.0',
        id: 'validate',
        method: 'agent.action.validateRun',
        params: {
          'action_id': 'action',
          'idempotency_key': 'key',
          'io': {'version': 1, 'mode': 'faithful', 'close_input': true},
        },
      ),
      const RpcDispatchContext(
        agentId: 'agent',
        clientToken: 'rotated',
        streamEmitter: null,
        limits: TransportLimits(),
        negotiatedExtensions: {},
      ),
    );
    expect(result['action_type'], 'executable');
    expect(result['definition_snapshot_hash'], 'old-definition');
    expect(result['would_replay_existing_execution'], isTrue);
    expect(result['existing_execution_id'], 'original');
    verifyZeroInteractions(journal);
    verifyZeroInteractions(repository);
    verifyZeroInteractions(triggers);
  });
}
