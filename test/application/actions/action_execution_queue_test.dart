import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/core/constants/agent_action_queue_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

AgentActionDefinitionPolicies _enqueuePolicies({
  Duration queueTimeout = const Duration(seconds: 30),
  int maxQueued = 8,
}) {
  return AgentActionDefinitionPolicies(
    queue: AgentActionQueuePolicy(
      maxQueued: maxQueued,
      queueTimeout: queueTimeout,
    ),
  );
}

void main() {
  group('ActionExecutionQueue dispose', () {
    test('fails pending items and rejects enqueue after dispose', () async {
      final queue = ActionExecutionQueue();
      final blocker = Completer<Result<String>>();
      final policies = _enqueuePolicies();

      unawaited(
        queue.enqueue(
          AgentActionQueueRequest<String>(
            actionId: 'a',
            executionId: 'running',
            policies: policies,
            task: () => blocker.future,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final pending = queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'pending',
          policies: policies,
          task: () async => const Success('should-not-run'),
        ),
      );

      queue.dispose();

      final pendingResult = await pending;
      check(pendingResult.isError()).isTrue();
      final pendingFailure = pendingResult.exceptionOrNull()!;
      check(pendingFailure).isA<ActionQueueFailure>();
      check((pendingFailure as ActionQueueFailure).code).equals(AgentActionFailureCode.queueDisposed);
      check(pendingFailure.context['reason']).equals(AgentActionQueueConstants.queueDisposedReason);

      final rejected = await queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'after-dispose',
          policies: policies,
          task: () async => const Success('nope'),
        ),
      );
      check(rejected.isError()).isTrue();
      check((rejected.exceptionOrNull()! as ActionQueueFailure).code)
          .equals(AgentActionFailureCode.queueDisposed);
      check(queue.isDisposed).isTrue();

      blocker.complete(const Success('done'));
    });

    test('disposeGracefully waits for in-flight then rejects new work', () async {
      final queue = ActionExecutionQueue();
      final blocker = Completer<Result<String>>();
      final policies = _enqueuePolicies();

      final running = queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'running',
          policies: policies,
          task: () => blocker.future,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      check(queue.runningCount).equals(1);

      final disposeFuture = queue.disposeGracefully(
        timeout: const Duration(seconds: 2),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      check(queue.isDisposed).isTrue();

      blocker.complete(const Success('ok'));
      final runningResult = await running;
      final disposeResult = await disposeFuture;

      check(runningResult.isSuccess()).isTrue();
      check(disposeResult.isSuccess()).isTrue();
      check(queue.runningCount).equals(0);

      final rejected = await queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'late',
          policies: policies,
          task: () async => const Success('nope'),
        ),
      );
      check(rejected.isError()).isTrue();
    });

    test('disposeGracefully times out when in-flight never finishes', () async {
      final queue = ActionExecutionQueue();
      final blocker = Completer<Result<String>>();

      unawaited(
        queue.enqueue(
          AgentActionQueueRequest<String>(
            actionId: 'a',
            executionId: 'stuck',
            policies: _enqueuePolicies(),
            task: () => blocker.future,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final disposeResult = await queue.disposeGracefully(
        timeout: const Duration(milliseconds: 30),
      );

      check(disposeResult.isError()).isTrue();
      final failure = disposeResult.exceptionOrNull()! as ActionQueueFailure;
      check(failure.code).equals(AgentActionFailureCode.queueDisposed);
      check(failure.context['timeout']).equals(true);
      check(failure.context['timeout_stage']).equals('shutdown');

      blocker.complete(const Success('late'));
    });

    test('thrown in-flight task completes with Failure and releases the slot', () async {
      final queue = ActionExecutionQueue();
      final pendingStarted = Completer<void>();

      final thrown = queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'throws',
          policies: _enqueuePolicies(),
          task: () async {
            throw StateError('task exploded');
          },
        ),
      );

      final thrownResult = await thrown;
      check(thrownResult.isError()).isTrue();
      final failure = thrownResult.exceptionOrNull()!;
      check(failure).isA<ActionRuntimeFailure>();
      check((failure as ActionRuntimeFailure).context['reason']).equals('unexpected_task_error');
      check(queue.runningCount).equals(0);

      final recovered = queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'after-throw',
          policies: _enqueuePolicies(),
          task: () async {
            pendingStarted.complete();
            return const Success('recovered');
          },
        ),
      );
      await pendingStarted.future.timeout(const Duration(seconds: 2));
      final recoveredResult = await recovered;
      check(recoveredResult.isSuccess()).isTrue();
    });

    test('thrown pending task completes with Failure and releases the slot', () async {
      final queue = ActionExecutionQueue();
      final blocker = Completer<Result<String>>();

      unawaited(
        queue.enqueue(
          AgentActionQueueRequest<String>(
            actionId: 'a',
            executionId: 'running',
            policies: _enqueuePolicies(),
            task: () => blocker.future,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final pending = queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'pending-throw',
          policies: _enqueuePolicies(),
          task: () async {
            throw StateError('pending exploded');
          },
        ),
      );

      blocker.complete(const Success('first'));
      final pendingResult = await pending;
      final idle = await queue.waitForActiveWorkers(timeout: const Duration(seconds: 2));
      check(idle.isSuccess()).isTrue();
      check(pendingResult.isError()).isTrue();
      check(pendingResult.exceptionOrNull()).isA<ActionRuntimeFailure>();
      check(queue.runningCount).equals(0);
    });

    test('cancelQueued after dispose returns disposed failure', () {
      final queue = ActionExecutionQueue()..dispose();

      final result = queue.cancelQueued(executionId: 'missing');
      check(result.isError()).isTrue();
      check((result.exceptionOrNull()! as ActionQueueFailure).code)
          .equals(AgentActionFailureCode.queueDisposed);
    });

    test('dispose is idempotent after pending items are failed', () async {
      final queue = ActionExecutionQueue();
      final blocker = Completer<Result<String>>();
      final policies = _enqueuePolicies(queueTimeout: const Duration(seconds: 5));

      unawaited(
        queue.enqueue(
          AgentActionQueueRequest<String>(
            actionId: 'a',
            executionId: 'running',
            policies: policies,
            task: () => blocker.future,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final pending = queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'pending-race',
          policies: policies,
          task: () async => const Success('queued-task'),
        ),
      );

      queue.dispose();
      queue.dispose();

      final pendingResult = await pending;
      check(pendingResult.isError()).isTrue();
      check((pendingResult.exceptionOrNull()! as ActionQueueFailure).code)
          .equals(AgentActionFailureCode.queueDisposed);

      blocker.complete(const Success('first'));
      await Future<void>.delayed(Duration.zero);
      check(queue.queuedCount).equals(0);
    });

    test('completing in-flight during disposeGracefully drains cleanly', () async {
      final queue = ActionExecutionQueue();
      final blocker = Completer<Result<String>>();

      final running = queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'running',
          policies: _enqueuePolicies(),
          task: () => blocker.future,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final disposeFuture = queue.disposeGracefully(
        timeout: const Duration(seconds: 2),
      );
      // Race: in-flight completion vs graceful drain waiter.
      blocker.complete(const Success('done'));

      final results = await Future.wait([running, disposeFuture]);
      check(results[0].isSuccess()).isTrue();
      check(results[1].isSuccess()).isTrue();
      check(queue.runningCount).equals(0);
    });

    test('validateRemoteAdmission rejects after dispose', () {
      final queue = ActionExecutionQueue()..dispose();
      final result = queue.validateRemoteAdmission(
        actionId: 'a',
        policies: _enqueuePolicies(),
      );
      check(result.isError()).isTrue();
      check((result.exceptionOrNull()! as ActionQueueFailure).code)
          .equals(AgentActionFailureCode.queueDisposed);
    });
  });

  group('ActionExecutionQueue timeout vs start race', () {
    test('timed-out pending is not started when drain races with timeout', () async {
      final queue = ActionExecutionQueue();
      final blocker = Completer<Result<String>>();
      final policies = _enqueuePolicies(queueTimeout: const Duration(milliseconds: 40));
      var pendingTaskStarted = false;

      unawaited(
        queue.enqueue(
          AgentActionQueueRequest<String>(
            actionId: 'a',
            executionId: 'running',
            policies: policies,
            task: () => blocker.future,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final pending = queue.enqueue(
        AgentActionQueueRequest<String>(
          actionId: 'a',
          executionId: 'timeout-race',
          policies: policies,
          task: () async {
            pendingTaskStarted = true;
            return const Success('started');
          },
        ),
      );

      final pendingResult = await pending;
      check(pendingResult.isError()).isTrue();
      check((pendingResult.exceptionOrNull()! as ActionQueueFailure).code)
          .equals(AgentActionFailureCode.queueTimeout);
      check(pendingTaskStarted).isFalse();

      blocker.complete(const Success('done'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      check(pendingTaskStarted).isFalse();
    });
  });
}
