import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

import 'action_io_hub_fixture.dart';

Future<void> verifyActionIoHubRevocation(
  ActionIoHubFixture hub,
  String actionId,
  Future<void> Function() revoke,
) async {
  final run = await hub.call(
    RpcRequest(
      jsonrpc: '2.0',
      id: 'revoke-run',
      method: 'agent.action.run',
      params: {
        'action_id': actionId,
        'idempotency_key': 'revoke-live-reader',
        'io': {'version': 1, 'mode': 'faithful', 'close_input': false},
      },
    ),
  );
  expect(run.error, isNull);
  final executionId = (run.result as Map)['execution_id'] as String;
  var completed = false;
  final read = hub
      .call(
        RpcRequest(
          jsonrpc: '2.0',
          id: 'revoke-reader',
          method: 'agent.action.readIo',
          params: {
            'execution_id': executionId,
            'after_sequence': 0,
            'max_bytes': ActionIoLimits.pageBytes,
            'wait_ms': 2000,
          },
        ),
      )
      .whenComplete(() => completed = true);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  expect(completed, isFalse);
  await revoke();
  final deniedRead = await read.timeout(const Duration(seconds: 5));
  expect(deniedRead.error, isNotNull);
  expect((deniedRead.error!.data as Map)['failure_code'], 'ACTION_IO_UNAUTHORIZED');
  expect(deniedRead.result, isNull);
  final deniedInput = await hub.call(
    RpcRequest(
      jsonrpc: '2.0',
      id: 'revoked-input',
      method: 'agent.action.sendInput',
      params: {'execution_id': executionId, 'message_id': 'never-admitted', 'sequence': 0, 'data_base64': 'AA=='},
    ),
  );
  expect(deniedInput.error, isNotNull);
  expect((deniedInput.error!.data as Map)['failure_code'], 'ACTION_IO_UNAUTHORIZED');
  expect(deniedInput.result, isNull);
}
