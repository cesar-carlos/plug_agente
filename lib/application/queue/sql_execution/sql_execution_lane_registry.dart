import 'dart:collection';

import 'package:plug_agente/application/queue/sql_execution/sql_execution_queued_request.dart';
import 'package:plug_agente/application/queue/sql_execution_kind.dart';
import 'package:plug_agente/application/queue/sql_queue_lane_scheduler.dart';

final class SqlExecutionLaneRegistry {
  SqlExecutionLaneRegistry()
    : _queues = {
        for (final kind in SqlExecutionKind.values) kind: Queue<SqlExecutionQueuedRequest<Object>>(),
      };

  static const SqlQueueLaneScheduler<SqlExecutionQueuedRequest<Object>> _laneScheduler =
      SqlQueueLaneScheduler<SqlExecutionQueuedRequest<Object>>();

  final Map<SqlExecutionKind, Queue<SqlExecutionQueuedRequest<Object>>> _queues;
  final SqlQueueLaneSchedulerState _laneSchedulerState = SqlQueueLaneSchedulerState();
  int queuedCount = 0;
  int nextSequence = 0;

  void enqueue<T extends Object>(SqlExecutionQueuedRequest<T> request) {
    _queues[request.kind]!.addLast(request as SqlExecutionQueuedRequest<Object>);
    queuedCount++;
  }

  bool remove(SqlExecutionQueuedRequest<Object> request) {
    final removed = _queues[request.kind]!.remove(request);
    if (removed) {
      queuedCount--;
    }
    return removed;
  }

  SqlExecutionQueuedRequest<Object>? takeNextEligible(
    bool Function(SqlExecutionQueuedRequest<Object> request) canStartRequest,
  ) {
    final request = _laneScheduler.takeNextEligibleRequest(
      queues: _queues,
      canStartRequest: canStartRequest,
      roundRobinState: _laneSchedulerState,
    );
    if (request == null) {
      return null;
    }
    queuedCount--;
    return request;
  }

  SqlExecutionQueuedRequest<Object>? takeNextQueued() {
    final request = _laneScheduler.takeNextQueuedRequest(
      queues: _queues,
      roundRobinState: _laneSchedulerState,
    );
    if (request == null) {
      return null;
    }
    queuedCount--;
    return request;
  }
}
