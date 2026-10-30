import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_io_session_supervisor.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';

import 'action_io_hub_fixture.dart';

Future<void> verifyActionIoHubShutdown({
  required ActionIoHubFixture hub,
  required String actionId,
  required ActionIoSessionSupervisor supervisor,
  required IActionIoSessionLookup sessions,
}) async {
  final run = await hub.call(
    RpcRequest(
      jsonrpc: '2.0',
      id: 'shutdown-run',
      method: 'agent.action.run',
      params: {
        'action_id': actionId,
        'idempotency_key': 'shutdown-active',
        'io': {'version': 1, 'mode': 'faithful', 'close_input': false, 'initial_input_base64': 'AP8='},
      },
    ),
  );
  expect(run.error, isNull);
  final id = (run.result as Map)['execution_id'] as String;
  var cursor = 0;
  var bytes = 0;
  for (var attempt = 0; attempt < 20 && bytes < 4; attempt++) {
    final page = await hub.call(
      RpcRequest(
        jsonrpc: '2.0',
        id: 'shutdown-read-$attempt',
        method: 'agent.action.readIo',
        params: {'execution_id': id, 'after_sequence': cursor, 'max_bytes': 65536, 'wait_ms': 1000},
      ),
    );
    expect(page.error, isNull);
    final result = page.result as Map;
    cursor = result['next_sequence'] as int;
    for (final event in result['events'] as List) {
      if ((event as Map)['type'] == 'output') bytes += base64Decode(event['data_base64'] as String).length;
    }
  }
  expect(bytes, 4);
  expect((await sessions.getExecutionSnapshot(id)).getOrThrow().processState, 'running');
  final stopping = supervisor.shutdown();
  expect(supervisor.accepting, isFalse);
  final refused = await hub.call(
    RpcRequest(
      jsonrpc: '2.0',
      id: 'shutdown-refused',
      method: 'agent.action.run',
      params: {
        'action_id': actionId,
        'idempotency_key': 'shutdown-refused',
        'io': {'version': 1, 'mode': 'faithful', 'close_input': true},
      },
    ),
  );
  expect(refused.error, isNotNull);
  expect((refused.error!.data as Map)['failure_code'], 'ACTION_IO_ADMISSION_CLOSED');
  (await stopping).getOrThrow();
  expect(supervisor.isSafelyIdle, isTrue);
  final terminal = (await sessions.getExecutionSnapshot(id)).getOrThrow();
  expect(terminal.processState, 'finished');
  expect(terminal.terminalAt, isNotNull);
}
