import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

import 'action_io_credential_fixture.dart';
import 'action_io_hub_fixture.dart';

Future<void> verifyActionIoHubOwnership({
  required ActionIoHubFixture hub,
  required ActionIoCredentialFixture credentials,
  required String executionId,
  required String actionId,
}) async {
  final owner = hub.credential;
  final other = await credentials.provision('other-${hub.clientId}', hub.agentId);
  hub.credential = other.tokenValue;
  try {
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
      'sendInput': {'execution_id': executionId, 'message_id': 'foreign-input', 'sequence': 4, 'data_base64': 'AA=='},
      'closeInput': {'execution_id': executionId, 'message_id': 'foreign-close', 'sequence': 4},
    };
    for (final entry in requests.entries) {
      final response = await hub.call(
        RpcRequest(
          jsonrpc: '2.0',
          id: 'foreign-${entry.key}',
          method: 'agent.action.${entry.key}',
          params: entry.value,
        ),
      );
      expect(response.result, isNull);
      expect(response.error, isNotNull, reason: entry.key);
      expect((response.error!.data as Map)['failure_code'], 'ACTION_IO_UNAUTHORIZED', reason: entry.key);
    }
    final found = await hub.call(
      RpcRequest(
        jsonrpc: '2.0',
        id: 'foreign-find',
        method: 'agent.action.findExecution',
        params: {'action_id': actionId, 'idempotency_key': 'key'},
      ),
    );
    expect(
      found.error,
      isNull,
      reason: 'find code=${found.error?.code}, validation=${(found.error?.data as Map?)?['technical_message']}',
    );
    expect((found.result as Map)['found'], isFalse);
    expect((found.result as Map)['execution_id'], isNull);
  } finally {
    hub.credential = owner;
  }
  final restored = await hub.call(
    RpcRequest(
      jsonrpc: '2.0',
      id: 'owner-restored',
      method: 'agent.action.getExecution',
      params: {'execution_id': executionId},
    ),
  );
  expect(restored.error, isNull);
  expect((restored.result as Map)['execution_id'], executionId);
}
