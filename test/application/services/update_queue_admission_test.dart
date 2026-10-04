import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  test('SQL freeze drains accepted work, rejects new work, and resumes only for its owner', () async {
    final queue = SqlExecutionQueue(maxQueueSize: 8, maxConcurrentWorkers: 1);
    final blocked = Completer<Result<int>>();
    final running = queue.submit(() => blocked.future);
    final waiting = queue.submit(() async => const Success(2));
    queue.pauseAdmissionForMaintenance('update1');
    expect((await queue.submit(() async => const Success(3))).isError(), isTrue);
    queue.resumeAdmissionAfterMaintenance('wrongOperation');
    expect((await queue.submit(() async => const Success(3))).isError(), isTrue);
    blocked.complete(const Success(1));
    expect((await running).getOrThrow(), 1);
    expect((await waiting).getOrThrow(), 2);
    queue.resumeAdmissionAfterMaintenance('update1');
    expect((await queue.submit(() async => const Success(3))).getOrThrow(), 3);
    queue.dispose();
  });
  test('action freeze preserves already admitted work and allows reversible resume', () async {
    final queue = ActionExecutionQueue();
    final blocker = Completer<Result<int>>();
    AgentActionQueueRequest<int> request(String id, Future<Result<int>> Function() task) => AgentActionQueueRequest(
      actionId: 'action',
      executionId: id,
      policies: const AgentActionDefinitionPolicies(),
      task: task,
    );
    final running = queue.enqueue(request('running', () => blocker.future));
    final waiting = queue.enqueue(request('waiting', () async => const Success(2)));
    queue.pauseAdmissionForMaintenance('update1');
    expect((await queue.enqueue(request('rejected', () async => const Success(3)))).isError(), isTrue);
    blocker.complete(const Success(1));
    expect((await running).getOrThrow(), 1);
    expect((await waiting).getOrThrow(), 2);
    queue.resumeAdmissionAfterMaintenance('update1');
    expect((await queue.enqueue(request('resumed', () async => const Success(3)))).getOrThrow(), 3);
    queue.dispose();
  });
}
