import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_io_session_supervisor.dart';
import 'package:plug_agente/application/services/update_maintenance_coordinator.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_control.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

final class _Session implements IActionIoSessionControl {
  final completed = Completer<Result<Unit>>();
  int runs = 0;
  int stops = 0;
  @override
  Future<Result<Unit>> runAndDrain() {
    runs++;
    return completed.future;
  }

  @override
  Future<Result<Unit>> stopAndDrain() {
    stops++;
    return completed.future;
  }
}

void main() {
  for (final throws in [false, true]) {
    test('late cancellation failure keeps shutdown uncertain (throws=$throws)', () async {
      final metrics = MetricsCollector();
      final supervisor = ActionIoSessionSupervisor(metrics: metrics.actionIoMetrics);
      final session = _PendingStopSession();
      (await supervisor.start('execution', () async => Success(session))).getOrThrow();
      supervisor.requestCancel('execution').getOrThrow();
      session.completed.complete(const Success(unit));
      await Future<void>.delayed(Duration.zero);
      expect(supervisor.activeCount, 1);
      expect(supervisor.isSafelyIdle, isFalse);
      final shutdown = supervisor.shutdown();
      if (throws) {
        session.stopCompleted.completeError(StateError('private-native-diagnostic'));
      } else {
        session.stopCompleted.complete(Failure(ActionRuntimeFailure('private-native-diagnostic')));
      }
      final result = await shutdown;
      expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
      expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_CLEANUP_FAILED');
      expect(supervisor.activeCount, 0);
      expect(supervisor.isSafelyIdle, isFalse);
      expect(supervisor.accepting, isFalse);
      expect(metrics.getSnapshot()['action_io_cleanup_unconfirmed'], 1);
      expect(metrics.getSnapshot().toString(), isNot(contains('private-native-diagnostic')));
      expect((await supervisor.shutdown()).isError(), isTrue);
      expect(session.stops, 1);
    });
  }
  test('normal completion retains ownership until concurrent cancellation cleanup settles', () async {
    final supervisor = ActionIoSessionSupervisor();
    final session = _PendingStopSession();
    (await supervisor.start('execution', () async => Success(session))).getOrThrow();
    expect(supervisor.requestCancel('execution').getOrThrow(), isTrue);
    session.completed.complete(const Success(unit));
    await Future<void>.delayed(Duration.zero);
    final retained = supervisor.activeCount;
    final idle = supervisor.isSafelyIdle;
    var drained = false;
    final shutdown = supervisor.shutdown().then((result) {
      drained = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    final drainedEarly = drained;
    session.stopCompleted.complete(const Success(unit));
    (await shutdown).getOrThrow();
    expect(retained, 1);
    expect(idle, isFalse);
    expect(drainedEarly, isFalse);
    expect(supervisor.isSafelyIdle, isTrue);
  });
  test('uncertain cleanup during maintenance refuses resume and exposes only aggregate metrics', () async {
    final metrics = MetricsCollector();
    final supervisor = ActionIoSessionSupervisor(metrics: metrics.actionIoMetrics);
    final session = _Session();
    (await supervisor.start('private-execution-id', () async => Success(session))).getOrThrow();
    supervisor.pauseForMaintenance('private-maintenance-id').getOrThrow();
    session.completed.complete(
      Failure(
        ActionRuntimeFailure.withContext(
          message: 'private-native-diagnostic',
          code: 'ACTION_OUTCOME_UNKNOWN',
          context: const {'payload': 'private-payload', 'credential': 'private-credential'},
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(supervisor.activeCount, 0);
    expect(supervisor.isSafelyIdle, isFalse);
    expect(supervisor.accepting, isFalse);
    expect(supervisor.resumeAfterMaintenance('private-maintenance-id').isError(), isTrue);
    var created = false;
    final refused = await supervisor.start('later', () async {
      created = true;
      return Success(_Session());
    });
    expect(refused.exceptionOrNull(), isA<ActionRuntimeFailure>());
    expect(created, isFalse);
    final snapshot = metrics.getSnapshot();
    expect(snapshot['action_io_sessions_owned'], 0);
    expect(snapshot['action_io_cleanup_unconfirmed'], 1);
    expect(snapshot.toString(), isNot(contains('private-')));
    expect((await supervisor.shutdown()).isError(), isTrue);
    expect((await supervisor.shutdown()).isError(), isTrue);
    expect(supervisor.accepting, isFalse);
  });

  test('background launch ownership survives preparation and shutdown waits for journal completion', () async {
    final metrics = MetricsCollector();
    final supervisor = ActionIoSessionSupervisor(metrics: metrics.actionIoMetrics);
    final completed = Completer<Result<Unit>>();
    var cancellation = 0;
    supervisor
        .launch(
          'execution',
          execute: () => completed.future,
          cancelPending: () async {
            cancellation++;
            return const Success(unit);
          },
        )
        .getOrThrow();
    expect(supervisor.isSafelyIdle, isFalse);
    expect(metrics.getSnapshot()['action_io_launches_owned'], 1);
    expect(metrics.getSnapshot()['action_io_sessions_owned'], 0);
    expect(
      supervisor
          .launch(
            'execution',
            execute: () async => throw StateError('duplicate'),
            cancelPending: () async => const Success(unit),
          )
          .isError(),
      isTrue,
    );
    var drained = false;
    final shutdown = supervisor.shutdown().then((result) {
      drained = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(cancellation, 1);
    expect(drained, isFalse);
    expect(metrics.getSnapshot()['action_io_launches_owned'], 1);
    expect((await supervisor.start('late', () async => throw StateError('late spawn'))).isError(), isTrue);
    completed.complete(const Success(unit));
    (await shutdown).getOrThrow();
    expect(supervisor.isSafelyIdle, isTrue);
    expect(metrics.getSnapshot()['action_io_launches_owned'], 0);
    expect(metrics.getSnapshot()['action_io_cleanup_unconfirmed'], 0);
  });

  test('unconfirmed background completion prevents journal shutdown', () async {
    final metrics = MetricsCollector();
    final supervisor = ActionIoSessionSupervisor(metrics: metrics.actionIoMetrics);
    supervisor
        .launch(
          'execution',
          execute: () async => throw StateError('uncertain'),
          cancelPending: () async => const Success(unit),
        )
        .getOrThrow();
    await Future<void>.delayed(Duration.zero);
    expect(supervisor.isSafelyIdle, isFalse);
    expect((await supervisor.shutdown()).isError(), isTrue);
    expect(metrics.getSnapshot()['action_io_launches_owned'], 0);
    expect(metrics.getSnapshot()['action_io_cleanup_unconfirmed'], 1);
  });

  test('cancel during creation stops once without resuming and retains ownership until cleanup', () async {
    final metrics = MetricsCollector();
    final supervisor = ActionIoSessionSupervisor(metrics: metrics.actionIoMetrics);
    final creating = Completer<Result<IActionIoSessionControl>>();
    final opening = supervisor.start('execution', () => creating.future);
    expect(metrics.getSnapshot()['action_io_sessions_owned'], 1);
    expect(supervisor.requestCancel('missing').getOrThrow(), isFalse);
    expect(supervisor.requestCancel('execution').getOrThrow(), isTrue);
    expect(supervisor.requestCancel('execution').getOrThrow(), isTrue);
    final session = _Session();
    creating.complete(Success(session));
    (await opening).getOrThrow();
    expect(session.runs, 0);
    expect(session.stops, 1);
    expect(metrics.getSnapshot()['action_io_sessions_owned'], 1);
    expect(supervisor.isSafelyIdle, isFalse);
    final shutdown = supervisor.shutdown();
    expect(session.stops, 1);
    session.completed.complete(const Success(unit));
    (await shutdown).getOrThrow();
    expect(supervisor.isSafelyIdle, isTrue);
    expect(metrics.getSnapshot()['action_io_sessions_owned'], 0);
    expect(supervisor.requestCancel('execution').getOrThrow(), isFalse);
  });

  test('cancel of a running session is idempotent and does not release uncertain cleanup', () async {
    final metrics = MetricsCollector();
    final supervisor = ActionIoSessionSupervisor(metrics: metrics.actionIoMetrics);
    final session = _Session();
    (await supervisor.start('execution', () async => Success(session))).getOrThrow();
    expect(session.runs, 1);
    expect(supervisor.requestCancel('execution').getOrThrow(), isTrue);
    expect(supervisor.requestCancel('execution').getOrThrow(), isTrue);
    expect(session.stops, 1);
    expect(supervisor.activeCount, 1);
    session.completed.complete(Failure(ActionRuntimeFailure('Native cleanup unknown')));
    expect((await supervisor.shutdown()).isError(), isTrue);
    expect(supervisor.isSafelyIdle, isFalse);
    expect(metrics.getSnapshot()['action_io_sessions_owned'], 0);
    expect(metrics.getSnapshot()['action_io_cleanup_unconfirmed'], 1);
  });

  test('maintenance defers without cancelling active I/O and restores admission', () async {
    final supervisor = ActionIoSessionSupervisor();
    final session = _Session();
    (await supervisor.start('execution', () async => Success(session))).getOrThrow();
    var now = DateTime(2026);
    var closed = false;
    final maintenance = UpdateMaintenanceCoordinator(
      freezeAdmission: () => supervisor.pauseForMaintenance('update').getOrThrow(),
      restoreAdmission: () => supervisor.resumeAfterMaintenance('update').getOrThrow(),
      isSafelyIdle: () => supervisor.isSafelyIdle,
      applyExitPolicies: (_) async => const Success(unit),
      flushAndCloseLocalData: () async {
        closed = true;
        return const Success(unit);
      },
      clock: () => now,
      wait: (duration) async => now = now.add(duration),
    );
    expect((await maintenance.prepare('update')).getOrThrow(), MaintenanceDecision.deferred);
    expect(supervisor.accepting, isTrue);
    expect(session.stops, 0);
    expect(closed, isFalse);
    session.completed.complete(const Success(unit));
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(minutes: 15));
    expect((await maintenance.prepare('update')).getOrThrow(), MaintenanceDecision.ready);
    expect(closed, isTrue);
    expect(supervisor.accepting, isFalse);
    (await supervisor.shutdown()).getOrThrow();
  });

  test('maintenance pauses new admission and resumes only for its owner operation', () async {
    final supervisor = ActionIoSessionSupervisor();
    final creating = Completer<Result<IActionIoSessionControl>>();
    final opening = supervisor.start('execution', () => creating.future);
    supervisor.pauseForMaintenance('update').getOrThrow();
    expect(supervisor.accepting, isFalse);
    expect(supervisor.isSafelyIdle, isFalse);
    expect(supervisor.resumeAfterMaintenance('other').isError(), isTrue);
    expect((await supervisor.start('late', () async => throw StateError('not admitted'))).isError(), isTrue);
    final session = _Session();
    creating.complete(Success(session));
    (await opening).getOrThrow();
    expect(session.runs, 1);
    expect(session.stops, 0);
    supervisor.resumeAfterMaintenance('update').getOrThrow();
    expect(supervisor.accepting, isTrue);
    session.completed.complete(const Success(unit));
    await Future<void>.delayed(Duration.zero);
    expect(supervisor.isSafelyIdle, isTrue);
    (await supervisor.shutdown()).getOrThrow();
    expect(supervisor.resumeAfterMaintenance('update').isError(), isTrue);
    expect(supervisor.pauseForMaintenance('another').isError(), isTrue);
  });

  test('shutdown waits for creation in progress then stops it without normal start', () async {
    final supervisor = ActionIoSessionSupervisor();
    final creating = Completer<Result<IActionIoSessionControl>>();
    final opening = supervisor.start('execution', () => creating.future);
    var stopped = false;
    final draining = supervisor.shutdown().then((result) {
      stopped = true;
      return result;
    });
    expect(supervisor.accepting, isFalse);
    expect(supervisor.activeCount, 1);
    expect((await supervisor.start('late', () async => throw StateError('must not create'))).isError(), isTrue);
    final session = _Session();
    creating.complete(Success(session));
    (await opening).getOrThrow();
    expect(session.runs, 0);
    expect(session.stops, 1);
    expect(stopped, isFalse);
    session.completed.complete(const Success(unit));
    (await draining).getOrThrow();
    expect(supervisor.activeCount, 0);
  });

  test('duplicate active registration is refused and shutdown awaits actual cleanup', () async {
    final supervisor = ActionIoSessionSupervisor();
    final session = _Session();
    (await supervisor.start('execution', () async => Success(session))).getOrThrow();
    expect(session.runs, 1);
    expect((await supervisor.start('execution', () async => throw StateError('duplicate'))).isError(), isTrue);
    final draining = supervisor.shutdown();
    expect(session.stops, 1);
    expect(supervisor.activeCount, 1);
    session.completed.complete(const Success(unit));
    (await draining).getOrThrow();
    (await supervisor.shutdown()).getOrThrow();
    expect(session.stops, 1);
  });

  test('uncertain creation or native cleanup never authorizes journal shutdown', () async {
    final failure = ActionRuntimeFailure.withContext(message: 'Uncertain.', code: 'ACTION_OUTCOME_UNKNOWN');
    final creation = ActionIoSessionSupervisor();
    expect((await creation.start('execution', () async => Failure(failure))).isError(), isTrue);
    expect((await creation.shutdown()).isError(), isTrue);
    final supervisor = ActionIoSessionSupervisor();
    final session = _Session();
    (await supervisor.start('execution', () async => Success(session))).getOrThrow();
    final draining = supervisor.shutdown();
    session.completed.complete(Failure(failure));
    expect((await draining).isError(), isTrue);
  });
}

final class _PendingStopSession extends _Session {
  final stopCompleted = Completer<Result<Unit>>();

  @override
  Future<Result<Unit>> stopAndDrain() {
    stops++;
    return stopCompleted.future;
  }
}
