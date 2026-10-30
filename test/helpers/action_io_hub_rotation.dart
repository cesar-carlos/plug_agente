import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/entities/agent_action_authorization_scopes.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

import 'action_io_credential_fixture.dart';
import 'action_io_hub_fixture.dart';

Future<void> verifyActionIoHubRotation({
  required ActionIoHubFixture hub,
  required ActionIoCredentialFixture credentials,
  required String tokenId,
  required String executionId,
  required String actionId,
}) async {
  const scopes = [
    AgentActionAuthorizationScopes.io,
    AgentActionAuthorizationScopes.run,
    AgentActionAuthorizationScopes.validateRun,
    AgentActionAuthorizationScopes.readExecution,
    AgentActionAuthorizationScopes.cancel,
  ];
  var version = 1;
  Future<String> rotate(List<String> granted, {List<String>? actionIds}) async {
    final outcome = (await UpdateClientToken(credentials.repository)(
      tokenId,
      ClientTokenCreateRequest(
        clientId: hub.clientId,
        agentId: hub.agentId,
        name: 'Isolated action I/O',
        allTables: false,
        allViews: false,
        rules: const [],
        payload: {
          'agent_action_scopes': granted,
          if (actionIds != null) 'agent_actions': {'action_ids': actionIds},
        },
      ),
      expectedVersion: version,
    )).getOrThrow();
    expect(outcome.didRotateToken, isTrue);
    expect(outcome.version, ++version);
    expect(outcome.tokenValue, isNotEmpty);
    return outcome.tokenValue!;
  }

  Future<RpcResponse> read(String id) => hub.call(
    RpcRequest(jsonrpc: '2.0', id: id, method: 'agent.action.getExecution', params: {'execution_id': executionId}),
  );

  final old = hub.credential;
  final replacement = await rotate(scopes, actionIds: [actionId]);
  expect(replacement == old, isFalse);
  expect((await read('rotation-old')).error, isNotNull);
  hub.credential = replacement;
  final retained = await read('rotation-retained');
  expect(retained.error, isNull);
  expect((retained.result as Map)['execution_id'], executionId);

  hub.credential = await rotate(scopes.where((scope) => scope != AgentActionAuthorizationScopes.io).toList());
  final denied = await read('rotation-without-io');
  expect(denied.error, isNotNull);
  expect((denied.error!.data as Map)['failure_code'], 'ACTION_IO_UNAUTHORIZED');
  hub.credential = await rotate(scopes);
  expect((await read('rotation-restored')).error, isNull);

  for (final allowed in <List<String>>[
    [],
    ['unrelated-action'],
  ]) {
    hub.credential = await rotate([AgentActionAuthorizationScopes.wildcard], actionIds: allowed);
    final requests = <String, Map<String, dynamic>>{
      'getExecution': {'execution_id': executionId},
      'cancel': {'execution_id': executionId},
      'readIo': {
        'execution_id': executionId,
        'after_sequence': 0,
        'max_bytes': ActionIoLimits.blockBytes,
        'wait_ms': 0,
      },
      'getInputStatus': {'execution_id': executionId, 'message_id': ActionIoLimits.initialMessageId},
      'sendInput': {'execution_id': executionId, 'message_id': 'allowlist-input', 'sequence': 4, 'data_base64': 'AA=='},
      'closeInput': {'execution_id': executionId, 'message_id': 'allowlist-close', 'sequence': 4},
      'findExecution': {'action_id': actionId, 'idempotency_key': 'key'},
      for (final method in ['run', 'validateRun'])
        method: {
          'action_id': actionId,
          'idempotency_key': 'allowlist-$version-$method',
          'io': {'version': 1, 'mode': 'faithful', 'close_input': true},
        },
    };
    for (final entry in requests.entries) {
      final response = await hub.call(
        RpcRequest(
          jsonrpc: '2.0',
          id: 'allowlist-$version-${entry.key}',
          method: 'agent.action.${entry.key}',
          params: entry.value,
        ),
      );
      expect(response.result, isNull);
      expect(response.error, isNotNull, reason: entry.key);
      expect((response.error!.data as Map)['failure_code'], 'ACTION_IO_UNAUTHORIZED', reason: entry.key);
    }
  }
  hub.credential = await rotate(scopes, actionIds: [actionId]);
  expect((await read('allowlist-restored')).error, isNull);
  final validation = await hub.call(
    RpcRequest(
      jsonrpc: '2.0',
      id: 'allowlist-validation-restored',
      method: 'agent.action.validateRun',
      params: {
        'action_id': actionId,
        'idempotency_key': 'allowlist-validation-restored',
        'io': {'version': 1, 'mode': 'faithful', 'close_input': true},
      },
    ),
  );
  expect(validation.error, isNull);
  expect((validation.result as Map)['valid'], isTrue);
  expect((validation.result as Map)['would_replay_existing_execution'], isFalse);
}
