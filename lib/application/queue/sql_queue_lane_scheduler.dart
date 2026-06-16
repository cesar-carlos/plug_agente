import 'dart:collection';

import 'package:plug_agente/application/queue/sql_execution_kind.dart';

/// Mutable round-robin cursor shared by [SqlQueueLaneScheduler] invocations.
final class SqlQueueLaneSchedulerState {
  int lastServedLaneIndex = -1;
}

/// Selects the next eligible queued SQL request respecting per-lane worker caps.
///
/// Uses round-robin across lanes so one hot lane cannot starve others while
/// preserving FIFO ordering within each lane.
final class SqlQueueLaneScheduler<T extends Object> {
  const SqlQueueLaneScheduler();

  static const List<SqlExecutionKind> laneOrder = SqlExecutionKind.values;

  T? takeNextEligibleRequest({
    required Map<SqlExecutionKind, Queue<T>> queues,
    required bool Function(T request) canStartRequest,
    required SqlQueueLaneSchedulerState roundRobinState,
  }) {
    return _takeNext(
      queues: queues,
      roundRobinState: roundRobinState,
      isEligible: canStartRequest,
    );
  }

  T? takeNextQueuedRequest({
    required Map<SqlExecutionKind, Queue<T>> queues,
    required SqlQueueLaneSchedulerState roundRobinState,
  }) {
    return _takeNext(
      queues: queues,
      roundRobinState: roundRobinState,
      isEligible: (_) => true,
    );
  }

  T? _takeNext({
    required Map<SqlExecutionKind, Queue<T>> queues,
    required SqlQueueLaneSchedulerState roundRobinState,
    required bool Function(T request) isEligible,
  }) {
    final laneCount = laneOrder.length;
    for (var offset = 1; offset <= laneCount; offset++) {
      final laneIndex = (roundRobinState.lastServedLaneIndex + offset) % laneCount;
      final kind = laneOrder[laneIndex];
      final queue = queues[kind];
      if (queue == null || queue.isEmpty) {
        continue;
      }
      final candidate = queue.first;
      if (!isEligible(candidate)) {
        continue;
      }
      roundRobinState.lastServedLaneIndex = laneIndex;
      return queue.removeFirst();
    }

    return null;
  }
}
