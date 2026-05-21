import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _FakeQueueMetrics implements ActionExecutionQueueMetricsCollector {
  int concurrencyReject = 0;
  int concurrencyIgnore = 0;
  int queueDepthFull = 0;
  int pendingEnqueued = 0;
  int idempotentReplay = 0;
  int runStarted = 0;
  int pendingWaitTimeout = 0;
  int pendingCancelled = 0;
  final List<Duration> dequeueWaits = <Duration>[];

  @override
  void recordConcurrencyReject() => concurrencyReject++;

  @override
  void recordConcurrencyIgnore() => concurrencyIgnore++;

  @override
  void recordQueueDepthFull() => queueDepthFull++;

  @override
  void recordPendingEnqueued() => pendingEnqueued++;

  @override
  void recordIdempotentReplay() => idempotentReplay++;

  @override
  void recordRunStarted() => runStarted++;

  @override
  void recordPendingWaitTimeout() => pendingWaitTimeout++;

  @override
  void recordPendingCancelled() => pendingCancelled++;

  @override
  void recordPendingDequeueWaitTime(Duration wait) => dequeueWaits.add(wait);
}

AgentActionDefinitionPolicies _policies(AgentActionQueuePolicy queue) {
  return AgentActionDefinitionPolicies(queue: queue);
}

void main() {
  test('validateRemoteAdmission increments reject and ignore when action is at capacity', () async {
    final metrics = _FakeQueueMetrics();
    final queue = ActionExecutionQueue(metrics: metrics);
    const busyPolicies = AgentActionDefinitionPolicies();
    const rejectPolicies = AgentActionDefinitionPolicies(
      queue: AgentActionQueuePolicy(
        concurrencyBehavior: AgentActionConcurrencyBehavior.reject,
      ),
    );
    const ignorePolicies = AgentActionDefinitionPolicies(
      queue: AgentActionQueuePolicy(
        concurrencyBehavior: AgentActionConcurrencyBehavior.ignore,
      ),
    );
    final blocker = Completer<Result<String>>();
    unawaited(
      queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'e0',
          policies: busyPolicies,
          task: () => blocker.future,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    check(queue.validateRemoteAdmission(actionId: 'a', policies: rejectPolicies).isError()).isTrue();
    check(queue.validateRemoteAdmission(actionId: 'a', policies: ignorePolicies).isError()).isTrue();
    check(metrics.concurrencyReject).equals(1);
    check(metrics.concurrencyIgnore).equals(1);

    blocker.complete(const Success('x'));
  });

  test('enqueue reject and queue depth full increment counters', () async {
    final metrics = _FakeQueueMetrics();
    final queue = ActionExecutionQueue(metrics: metrics);
    final blocker = Completer<Result<String>>();
    const runningPolicies = AgentActionDefinitionPolicies(
      queue: AgentActionQueuePolicy(
        maxQueued: 2,
      ),
    );
    unawaited(
      queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'x',
          executionId: 'e1',
          policies: runningPolicies,
          task: () => blocker.future,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final rejectPolicies = _policies(
      const AgentActionQueuePolicy(
        concurrencyBehavior: AgentActionConcurrencyBehavior.reject,
      ),
    );
    final rejectResult = await queue.enqueue(
      AgentActionQueueRequest<String>(
        actionId: 'x',
        executionId: 'e2',
        policies: rejectPolicies,
        task: () async => const Success('n'),
      ),
    );
    check(rejectResult.isError()).isTrue();
    check(metrics.concurrencyReject).equals(1);

    unawaited(
      queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'y',
          executionId: 'e-y1',
          policies: runningPolicies,
          task: () => blocker.future,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    const fullPolicies = AgentActionDefinitionPolicies(
      queue: AgentActionQueuePolicy(
        maxQueued: 0,
      ),
    );
    final fullResult = await queue.enqueue(
      AgentActionQueueRequest<String>(
        actionId: 'y',
        executionId: 'e-y2',
        policies: fullPolicies,
        task: () async => const Success('z'),
      ),
    );
    check(fullResult.isError()).isTrue();
    check(metrics.queueDepthFull).equals(1);

    blocker.complete(const Success('done'));
  });

  test('idempotent replay increments counter', () async {
    final metrics = _FakeQueueMetrics();
    final queue = ActionExecutionQueue(metrics: metrics);
    const policies = AgentActionDefinitionPolicies(
      queue: AgentActionQueuePolicy(concurrencyBehavior: AgentActionConcurrencyBehavior.allowParallel),
    );
    final first = queue.enqueue(
      AgentActionQueueRequest<String>(
        actionId: 'a',
        executionId: 'e1',
        policies: policies,
        idempotencyKey: 'k1',
        task: () async => const Success('v'),
      ),
    );
    final second = queue.enqueue(
      AgentActionQueueRequest<String>(
        actionId: 'a',
        executionId: 'e2',
        policies: policies,
        idempotencyKey: 'k1',
        task: () async => const Success('other'),
      ),
    );
    final firstResult = await first;
    final secondResult = await second;
    check(firstResult.isSuccess()).isTrue();
    check(secondResult.isSuccess()).isTrue();
    check(firstResult.getOrThrow()).equals(secondResult.getOrThrow());
    check(metrics.idempotentReplay).equals(1);
    check(metrics.runStarted).equals(1);
  });

  test('pending dequeue records wait when blocked task completes', () async {
    final metrics = _FakeQueueMetrics();
    final queue = ActionExecutionQueue(metrics: metrics);
    const policies = AgentActionDefinitionPolicies(
      queue: AgentActionQueuePolicy(
        maxQueued: 2,
      ),
    );
    final blocker = Completer<Result<String>>();
    unawaited(
      queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'p',
          executionId: 'run-1',
          policies: policies,
          task: () => blocker.future,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final second = queue.enqueue(
      AgentActionQueueRequest<String>(
        actionId: 'p',
        executionId: 'run-2',
        policies: policies,
        task: () async => const Success('second'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    check(metrics.pendingEnqueued).equals(1);

    blocker.complete(const Success('first'));
    await second;
    check(metrics.runStarted).equals(2);
    check(metrics.dequeueWaits).length.equals(1);
  });

  test('pending wait timeout increments counter', () async {
    final metrics = _FakeQueueMetrics();
    final queue = ActionExecutionQueue(metrics: metrics);
    const policies = AgentActionDefinitionPolicies(
      queue: AgentActionQueuePolicy(
        maxQueued: 2,
        queueTimeout: Duration(milliseconds: 30),
      ),
    );
    final blocker = Completer<Result<String>>();
    unawaited(
      queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 't',
          executionId: 't1',
          policies: policies,
          task: () => blocker.future,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final waiter = queue.enqueue(
      AgentActionQueueRequest<String>(
        actionId: 't',
        executionId: 't2',
        policies: policies,
        task: () async => const Success('second'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final result = await waiter;
    check(result.isError()).isTrue();
    check(metrics.pendingWaitTimeout).equals(1);

    blocker.complete(const Success('first'));
  });

  test('cancelQueued increments pending cancelled counter', () async {
    final metrics = _FakeQueueMetrics();
    final queue = ActionExecutionQueue(metrics: metrics);
    const policies = AgentActionDefinitionPolicies(
      queue: AgentActionQueuePolicy(
        maxQueued: 2,
      ),
    );
    final blocker = Completer<Result<String>>();
    unawaited(
      queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'c',
          executionId: 'c1',
          policies: policies,
          task: () => blocker.future,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    unawaited(
      queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'c',
          executionId: 'c2',
          policies: policies,
          task: () async => const Success('x'),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final cancel = queue.cancelQueued(executionId: 'c2');
    check(cancel.isSuccess()).isTrue();
    check(metrics.pendingCancelled).equals(1);

    blocker.complete(const Success('first'));
  });

  test('MetricsCollector exposes agent_action_queue counters in snapshot', () async {
    final collector = MetricsCollector();
    final queue = ActionExecutionQueue(metrics: collector);
    const policies = AgentActionDefinitionPolicies(
      queue: AgentActionQueuePolicy(
        maxQueued: 2,
        concurrencyBehavior: AgentActionConcurrencyBehavior.allowParallel,
      ),
    );
    await queue.enqueue(
      AgentActionQueueRequest<String>(
        actionId: 'm',
        executionId: 'm1',
        policies: policies,
        task: () async => const Success('ok'),
      ),
    );
    final snapshot = collector.getSnapshot();
    check(snapshot['agent_action_queue_run_started'] as int? ?? 0).equals(1);
    check((snapshot['agent_action_queue_wait_sample_count'] as num?)?.toInt() ?? 0).equals(0);
  });
}
