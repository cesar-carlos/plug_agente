import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_session_supervisor.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:result_dart/result_dart.dart';

import 'action_io_hub_fixture.dart';

/// Holds the real shared queue while remote run is admitted and cancelled.
Future<void> verifyActionIoQueuedCancellation(
  ActionIoHubFixture hub,
  ActionExecutionQueue queue,
  ActionIoSessionSupervisor supervisor,
  String actionId,
) async {
  final entered = Completer<void>();
  final release = Completer<Result<Unit>>();
  final blocker = queue.enqueue(
    AgentActionQueueRequest<Unit>(
      actionId: actionId,
      executionId: 'fixture-queue-blocker',
      policies: const AgentActionDefinitionPolicies(),
      task: () {
        entered.complete();
        return release.future;
      },
    ),
  );
  await entered.future;
  late String id;
  try {
    final run = await hub.call(
      RpcRequest(
        jsonrpc: '2.0',
        id: 'queued-run',
        method: 'agent.action.run',
        params: {
          'action_id': actionId,
          'idempotency_key': 'queued-cancel-fixture',
          'io': {'version': 1, 'mode': 'faithful', 'close_input': false},
        },
      ),
    );
    expect(run.error, isNull);
    id = (run.result as Map)['execution_id'] as String;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (queue.queuedCount == 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(queue.queuedCount, 1);
    final cancelled = await hub.call(
      RpcRequest(jsonrpc: '2.0', id: 'queued-cancel', method: 'agent.action.cancel', params: {'execution_id': id}),
    );
    expect(cancelled.error, isNull);
    expect((cancelled.result as Map)['status'], 'cancelled');
    final read = await hub.call(
      RpcRequest(
        jsonrpc: '2.0',
        id: 'queued-cancel-read',
        method: 'agent.action.readIo',
        params: {
          'execution_id': id,
          'after_sequence': 0,
          'max_bytes': ActionIoLimits.blockBytes,
          'wait_ms': 0,
        },
      ),
    );
    expect(read.error, isNull);
    final page = read.result as Map;
    expect(page['terminal'], isTrue);
    final exited = (page['events'] as List).cast<Map<String, dynamic>>().singleWhere(
      (event) => event['type'] == 'process_exited',
    );
    expect(exited.containsKey('exit_code'), isTrue);
    expect(exited['exit_code'], isNull);
  } finally {
    release.complete(const Success(unit));
    (await blocker).getOrThrow();
  }
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!supervisor.isSafelyIdle && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(supervisor.isSafelyIdle, isTrue);
  expect(queue.runningCount, 0);
  expect(queue.queuedCount, 0);
  final finalState = await hub.call(
    RpcRequest(jsonrpc: '2.0', id: 'queued-final', method: 'agent.action.getExecution', params: {'execution_id': id}),
  );
  expect(finalState.error, isNull);
  expect((finalState.result as Map)['status'], 'cancelled');
}

/// Cancels an actual running pipe process while a remote read is waiting.
Future<void> verifyActionIoHubCancellation(ActionIoHubFixture hub, String actionId) async {
  final request = RpcRequest(
    jsonrpc: '2.0',
    id: 'cancel-run',
    method: 'agent.action.run',
    params: {
      'action_id': actionId,
      'idempotency_key': 'cancel-live-reader',
      'io': {'version': 1, 'mode': 'faithful', 'close_input': false},
    },
  );
  final run = await hub.call(request);
  expect(run.error, isNull);
  final executionId = (run.result as Map)['execution_id'] as String;

  var stateQuery = 0;
  Future<Map<String, dynamic>> waitForState(String state) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      final response = await hub.call(
        RpcRequest(
          jsonrpc: '2.0',
          id: '$state-${stateQuery++}',
          method: 'agent.action.getExecution',
          params: {'execution_id': executionId},
        ),
      );
      expect(response.error, isNull, reason: '${response.error?.code}: ${response.error?.message}');
      final result = response.result as Map<String, dynamic>;
      if ((result['io'] as Map)['process_state'] == state) return result;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Fixture process did not reach $state.');
  }

  await waitForState('running');
  // A short caller budget must leave the response reserve instead of waiting
  // for the requested twenty seconds. The process itself remains running.
  final boundedRead = await hub.call(
    RpcRequest(
      jsonrpc: '2.0',
      id: 'short-budget-reader',
      method: 'agent.action.readIo',
      params: {
        'execution_id': executionId,
        'after_sequence': 0,
        'max_bytes': ActionIoLimits.pageBytes,
        'wait_ms': 20000,
      },
    ),
    timeoutMs: 4000,
  );
  expect(boundedRead.error, isNull, reason: '${boundedRead.error?.code}: ${boundedRead.error?.message}');
  expect((boundedRead.result as Map)['events'], isEmpty);
  expect((boundedRead.result as Map)['terminal'], isFalse);
  await waitForState('running');
  var readerCompleted = false;
  final reader = hub
      .call(
        RpcRequest(
          jsonrpc: '2.0',
          id: 'cancel-reader',
          method: 'agent.action.readIo',
          params: {
            'execution_id': executionId,
            'after_sequence': 0,
            'max_bytes': ActionIoLimits.pageBytes,
            'wait_ms': 20000,
          },
        ),
      )
      .whenComplete(() => readerCompleted = true);
  await Future<void>.delayed(const Duration(milliseconds: 150));
  expect(readerCompleted, isFalse);
  final cancelled = await hub.call(
    RpcRequest(
      jsonrpc: '2.0',
      id: 'cancel-request',
      method: 'agent.action.cancel',
      params: {'execution_id': executionId},
    ),
  );
  expect(cancelled.error, isNull, reason: '${cancelled.error?.code}: ${cancelled.error?.message}');
  final output = await reader.timeout(const Duration(seconds: 5));
  expect(output.error, isNull);
  final terminal = await waitForState('finished');
  expect(terminal['status'], 'cancelled');
  expect((output.result as Map)['events'], isNotEmpty);
  final duplicate = await hub.call(
    RpcRequest(jsonrpc: '2.0', id: 'cancel-terminal-duplicate', method: request.method, params: request.params),
  );
  expect(duplicate.error, isNull);
  expect((duplicate.result as Map)['execution_id'], executionId);
  expect((duplicate.result as Map)['status'], 'cancelled');
}
