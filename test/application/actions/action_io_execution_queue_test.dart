import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_session_supervisor.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_control.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _Session implements IActionIoSessionControl {
  final cleanup = Completer<Result<Unit>>();
  @override
  Future<Result<Unit>> runAndDrain() => cleanup.future;
  @override
  Future<Result<Unit>> stopAndDrain() => cleanup.future;
}

void main() {
  for (final shutdown in [false, true]) {
    test('${shutdown ? 'shutdown' : 'maintenance'} during preparation refuses native creation', () async {
      final shared = ActionExecutionQueue();
      addTearDown(shared.dispose);
      final supervisor = ActionIoSessionSupervisor();
      final queue = ActionIoExecutionQueue(shared, supervisor);
      final preparing = Completer<void>();
      final prepared = Completer<Result<Unit>>();
      var creations = 0;
      final pending = queue.enqueue(
        actionId: 'a',
        executionId: 'preparing',
        policies: const AgentActionDefinitionPolicies(),
        prepare: () {
          preparing.complete();
          return prepared.future;
        },
        create: () async {
          creations++;
          return Success(_Session()..cleanup.complete(const Success(unit)));
        },
      );
      await preparing.future;
      if (shutdown) {
        (await supervisor.shutdown()).getOrThrow();
      } else {
        supervisor.pauseForMaintenance('update').getOrThrow();
      }
      prepared.complete(const Success(unit));
      final result = await pending;
      expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
      expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_ADMISSION_CLOSED');
      expect(creations, 0);
      expect(shared.runningCount, 0);
      expect(shared.queuedCount, 0);
      expect(supervisor.isSafelyIdle, isTrue);
      if (!shutdown) {
        supervisor.resumeAfterMaintenance('update').getOrThrow();
        expect(supervisor.accepting, isTrue);
      }
      (await supervisor.shutdown()).getOrThrow();
    });
  }
  for (final cancel in [false, true]) {
    test('I/O waiting gauge releases once on ${cancel ? 'cancellation' : 'start'}', () async {
      final shared = ActionExecutionQueue();
      final supervisor = ActionIoSessionSupervisor();
      final metrics = MetricsCollector();
      final queue = ActionIoExecutionQueue(shared, supervisor, metrics: metrics.actionIoMetrics);
      final unblock = Completer<Result<Unit>>();
      final entered = Completer<void>();
      final legacy = shared.enqueue(
        AgentActionQueueRequest<Unit>(
          actionId: 'a',
          executionId: 'legacy',
          policies: const AgentActionDefinitionPolicies(),
          task: () {
            entered.complete();
            return unblock.future;
          },
        ),
      );
      await entered.future;
      var created = false;
      final pending = queue.enqueue(
        actionId: 'a',
        executionId: 'faithful',
        policies: const AgentActionDefinitionPolicies(),
        create: () async {
          created = true;
          expect(metrics.getSnapshot()['action_io_queue_waiting'], 0);
          return Success(_Session()..cleanup.complete(const Success(unit)));
        },
      );
      expect(metrics.getSnapshot()['action_io_queue_waiting'], 1);
      expect(shared.queuedCount, 1);
      if (cancel) queue.cancelPending('faithful').getOrThrow();
      unblock.complete(const Success(unit));
      (await legacy).getOrThrow();
      final result = await pending;
      expect(result.isError(), cancel);
      expect(created, !cancel);
      expect(metrics.getSnapshot()['action_io_queue_waiting'], 0);
      (await supervisor.shutdown()).getOrThrow();
      shared.dispose();
    });
  }

  test('preparation refusal preserves its failure without entering native creation', () async {
    final shared = ActionExecutionQueue();
    final supervisor = ActionIoSessionSupervisor();
    final denied = ActionAuthorizationFailure('Credential revoked');
    var created = false;
    final result = await ActionIoExecutionQueue(shared, supervisor).enqueue(
      actionId: 'a',
      executionId: 'revoked',
      policies: const AgentActionDefinitionPolicies(),
      prepare: () async => Failure(denied),
      create: () async {
        created = true;
        return Success(_Session());
      },
    );
    expect(result.exceptionOrNull(), same(denied));
    expect(created, isFalse);
    expect(shared.runningCount, 0);
    expect(supervisor.isSafelyIdle, isTrue);
    (await supervisor.shutdown()).getOrThrow();
    shared.dispose();
  });
  test('closed supervisor refuses before creation without quarantining a slot', () async {
    final shared = ActionExecutionQueue();
    final supervisor = ActionIoSessionSupervisor();
    (await supervisor.shutdown()).getOrThrow();
    var created = false;
    final result = await ActionIoExecutionQueue(shared, supervisor).enqueue(
      actionId: 'a',
      executionId: 'refused',
      policies: const AgentActionDefinitionPolicies(),
      create: () async {
        created = true;
        return Success(_Session());
      },
    );
    expect(result.isError(), isTrue);
    expect(created, isFalse);
    expect(shared.runningCount, 0);
    shared.dispose();
  });
  test('uncertain cleanup keeps the shared slot and prevents the next task', () async {
    final shared = ActionExecutionQueue();
    final supervisor = ActionIoSessionSupervisor();
    final queue = ActionIoExecutionQueue(shared, supervisor);
    final session = _Session();
    final faithful = queue.enqueue(
      actionId: 'a',
      executionId: 'uncertain',
      policies: const AgentActionDefinitionPolicies(),
      create: () async => Success(session),
    );
    await Future<void>.delayed(Duration.zero);
    session.cleanup.complete(Failure(ActionRuntimeFailure('Cleanup unconfirmed')));
    expect((await faithful).isError(), isTrue);
    expect(shared.runningCount, 1);
    var ran = false;
    final next = await shared.enqueue(
      AgentActionQueueRequest<Unit>(
        actionId: 'a',
        executionId: 'next',
        policies: const AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(concurrencyBehavior: AgentActionConcurrencyBehavior.allowParallel),
        ),
        task: () async {
          ran = true;
          return const Success(unit);
        },
      ),
    );
    expect(next.isError(), isTrue);
    expect(ran, isFalse);
    shared.dispose();
    expect((await supervisor.shutdown()).isError(), isTrue);
  });
  test('legacy action waits for faithful native cleanup in the shared queue', () async {
    final shared = ActionExecutionQueue();
    final supervisor = ActionIoSessionSupervisor();
    final queue = ActionIoExecutionQueue(shared, supervisor);
    final session = _Session();
    var creations = 0;
    var legacyRan = false;
    final faithful = queue.enqueue(
      actionId: 'a',
      executionId: 'faithful',
      policies: const AgentActionDefinitionPolicies(),
      create: () async {
        creations++;
        return Success(session);
      },
    );
    await Future<void>.delayed(Duration.zero);
    final legacy = shared.enqueue(
      AgentActionQueueRequest<Unit>(
        actionId: 'a',
        executionId: 'legacy',
        policies: const AgentActionDefinitionPolicies(),
        task: () async {
          legacyRan = true;
          return const Success(unit);
        },
      ),
    );
    expect(shared.runningCount, 1);
    expect(shared.queuedCount, 1);
    expect(legacyRan, isFalse);
    session.cleanup.complete(const Success(unit));
    expect((await faithful).isSuccess(), isTrue);
    expect((await legacy).isSuccess(), isTrue);
    expect(creations, 1);
    expect(legacyRan, isTrue);
    expect(shared.runningCount, 0);
    (await supervisor.shutdown()).getOrThrow();
  });
}
