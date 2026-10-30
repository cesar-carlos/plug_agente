import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';

import 'action_io_hub_fixture.dart';

Future<void> verifyActionIoHubBlockedInput(
  ActionIoHubFixture hub,
  IAgentActionRepository repository,
  AgentActionDefinition original, {
  Future<void> Function(String executionId)? onWriting,
}) async {
  final config = original.config as ExecutableActionConfig;
  var saved = original.copyWith(
    config: ExecutableActionConfig(
      executablePath: config.executablePath,
      arguments: const ['-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60'],
    ),
  );
  saved = saved.copyWith(
    policies: saved.policies.copyWith(
      remote: saved.policies.remote.copyWith(
        riskFingerprint: const AgentActionDefinitionSnapshotter().riskFingerprint(saved),
      ),
    ),
  );
  (await repository.saveDefinition(saved)).getOrThrow();
  try {
    final run = await hub.call(
      RpcRequest(
        jsonrpc: '2.0',
        id: 'blocked-run',
        method: 'agent.action.run',
        params: <String, dynamic>{
          'action_id': saved.id,
          'idempotency_key': 'blocked-input',
          'io': {'version': 1, 'mode': 'faithful', 'close_input': false},
        },
      ),
    );
    expect(run.error, isNull);
    final executionId = (run.result as Map)['execution_id'] as String;
    final send = RpcRequest(
      jsonrpc: '2.0',
      id: 'blocked-send',
      method: 'agent.action.sendInput',
      params: <String, dynamic>{
        'execution_id': executionId,
        'message_id': 'blocked',
        'sequence': 0,
        'data_base64': base64Encode(List<int>.filled(65536, 65)),
      },
    );
    final admitted = await hub.call(send);
    expect(admitted.error, isNull);
    var observedWriting = false;
    Map<dynamic, dynamic>? receipt;
    var statusSequence = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      final status = await hub.call(
        RpcRequest(
          jsonrpc: '2.0',
          id: 'blocked-status-${statusSequence++}',
          method: 'agent.action.getInputStatus',
          params: <String, dynamic>{'execution_id': executionId, 'message_id': 'blocked'},
        ),
      );
      expect(status.error, isNull, reason: '${status.error?.code}: ${status.error?.message} ${status.error?.data}');
      receipt = status.result as Map;
      observedWriting |= receipt['state'] == 'writing';
      if (receipt['state'] == 'writing' && statusSequence >= 3 && onWriting != null) {
        await onWriting(executionId);
      }
      if (receipt['state'] == 'unknown') break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(observedWriting, isTrue);
    expect(receipt?['state'], 'unknown');
    expect(receipt?['confirmed_bytes'], isNull);
    final duplicate = await hub.call(
      RpcRequest(
        jsonrpc: '2.0',
        id: 'blocked-send-duplicate',
        method: send.method,
        params: send.params,
      ),
    );
    expect(duplicate.error, isNull);
    expect((duplicate.result as Map)['state'], 'unknown');
  } finally {
    (await repository.saveDefinition(original)).getOrThrow();
  }
}
