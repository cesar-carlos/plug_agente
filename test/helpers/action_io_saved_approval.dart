import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';

/// Checks stale local approval through the same RPC path as the original run.
Future<void> verifyActionIoSavedApproval({
  required IAgentActionRepository repository,
  required AgentActionDefinition definition,
  required RpcRequest original,
  required String executionId,
  required Future<RpcResponse> Function(RpcRequest) dispatch,
}) async {
  final config = definition.config as ExecutableActionConfig;
  final changed = definition.copyWith(
    config: ExecutableActionConfig(
      executablePath: config.executablePath,
      workingDirectory: config.workingDirectory,
      arguments: [...config.arguments, 'changed-local-argument'],
    ),
  );
  expect(
    const AgentActionDefinitionSnapshotter().riskFingerprint(changed),
    isNot(definition.policies.remote.riskFingerprint),
  );
  (await repository.saveDefinition(changed)).getOrThrow();
  try {
    final duplicate = await dispatch(
      RpcRequest(
        jsonrpc: '2.0',
        id: 'changed-definition-duplicate',
        method: original.method,
        params: original.params,
      ),
    );
    expect(duplicate.error, isNull);
    expect((duplicate.result as Map)['execution_id'], executionId);
    expect((duplicate.result as Map)['status'], 'succeeded');
    final denied = await dispatch(
      RpcRequest(
        jsonrpc: '2.0',
        id: 'changed-definition-new-run',
        method: original.method,
        params: <String, dynamic>{
          ...Map<String, dynamic>.from(original.params! as Map),
          'idempotency_key': 'stale-approval-new-key',
        },
      ),
    );
    expect(denied.result, isNull);
    expect(denied.error, isNotNull);
    expect((denied.error!.data as Map)['failure_code'], 'ACTION_IO_NOT_APPROVED');
  } finally {
    (await repository.saveDefinition(definition)).getOrThrow();
  }
}
