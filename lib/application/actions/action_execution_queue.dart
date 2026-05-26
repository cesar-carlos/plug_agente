import 'dart:async';
import 'dart:collection';

import 'package:plug_agente/core/constants/agent_action_queue_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentActionQueuedTask<T extends Object> = Future<Result<T>> Function();

class AgentActionQueueRequest<T extends Object> {
  const AgentActionQueueRequest({
    required this.actionId,
    required this.executionId,
    required this.policies,
    required this.task,
    this.idempotencyKey,
  });

  final String actionId;
  final String executionId;
  final String? idempotencyKey;
  final AgentActionDefinitionPolicies policies;
  final AgentActionQueuedTask<T> task;
}

class ActionExecutionQueue {
  ActionExecutionQueue({ActionExecutionQueueMetricsCollector? metrics}) : _metrics = metrics;

  final ActionExecutionQueueMetricsCollector? _metrics;

  final Map<String, int> _runningByActionId = <String, int>{};
  final Map<String, Queue<_PendingActionTask<Object>>> _pendingByActionId =
      <String, Queue<_PendingActionTask<Object>>>{};
  final Map<String, Future<Result<Object>>> _idempotentResults = <String, Future<Result<Object>>>{};

  int get runningCount => _runningByActionId.values.fold(0, (total, count) => total + count);

  int get queuedCount => _pendingByActionId.values.fold(0, (total, queue) => total + queue.length);

  Result<AgentActionCancellationResult> cancelQueued({
    required String executionId,
  }) {
    final trimmedExecutionId = executionId.trim();
    for (final entry in _pendingByActionId.entries.toList(growable: false)) {
      final pending = entry.value.where((task) => task.request.executionId == trimmedExecutionId).firstOrNull;
      if (pending == null) {
        continue;
      }

      entry.value.remove(pending);
      if (entry.value.isEmpty) {
        _pendingByActionId.remove(entry.key);
      }
      pending.cancel();
      return Success(
        AgentActionCancellationResult(
          executionId: trimmedExecutionId,
          status: AgentActionExecutionStatus.cancelled,
          killed: false,
          message: 'Execution cancelled before starting.',
        ),
      );
    }

    return Failure(
      ActionNotFoundFailure.withContext(
        message: 'Queued action execution was not found.',
        code: AgentActionFailureCode.queueItemNotFound,
        context: {
          'execution_id': trimmedExecutionId,
          'reason': AgentActionQueueConstants.queuedExecutionNotFoundReason,
          'user_message': 'Execution not found in the action queue.',
        },
      ),
    );
  }

  /// Validates queue admission without enqueueing or running a task.
  ///
  /// Used by `agent.action.validateRun` to surface the same concurrency and
  /// depth limits as a real [enqueue] call.
  Result<void> validateRemoteAdmission({
    required String actionId,
    required AgentActionDefinitionPolicies policies,
  }) {
    final queuePolicy = policies.queue;
    if (queuePolicy.concurrencyBehavior == AgentActionConcurrencyBehavior.allowParallel ||
        _canRunNow(actionId, queuePolicy)) {
      return const Success(unit);
    }

    return switch (queuePolicy.concurrencyBehavior) {
      AgentActionConcurrencyBehavior.reject => () {
        _metrics?.recordConcurrencyReject();
        return Failure(
          ActionQueueFailure.withContext(
            message: 'Action execution would be rejected because the concurrency limit was reached.',
            code: AgentActionFailureCode.queueConcurrencyRejected,
            context: {
              'action_id': actionId,
              'reason': AgentActionQueueConstants.concurrencyLimitReachedReason,
              'user_message': 'The action is already running and the current policy rejects simultaneous executions.',
            },
          ),
        );
      }(),
      AgentActionConcurrencyBehavior.ignore => () {
        _metrics?.recordConcurrencyIgnore();
        return Failure(
          ActionQueueFailure.withContext(
            message: 'Action execution would be ignored because another execution is already running.',
            code: AgentActionFailureCode.queueIgnored,
            context: {
              'action_id': actionId,
              'reason': AgentActionQueueConstants.concurrencyIgnoreReason,
              'user_message':
                  'The action is already running and this request would be ignored by the configured policy.',
            },
          ),
        );
      }(),
      AgentActionConcurrencyBehavior.enqueue => _validateEnqueueHeadroom(actionId, queuePolicy.maxQueued),
      AgentActionConcurrencyBehavior.allowParallel => const Success(unit),
    };
  }

  Result<void> _validateEnqueueHeadroom(String actionId, int maxQueued) {
    final queue = _pendingByActionId[actionId];
    final depth = queue?.length ?? 0;
    if (depth >= maxQueued) {
      _metrics?.recordQueueDepthFull();
      return Failure(
        ActionQueueFailure.withContext(
          message: 'Action execution queue is full.',
          code: AgentActionFailureCode.queueFull,
          context: {
            'action_id': actionId,
            'max_queued': maxQueued,
            'reason': AgentActionQueueConstants.queueFullReason,
            'user_message': 'The action queue is full. Wait for a running execution to finish and try again.',
          },
        ),
      );
    }

    return const Success(unit);
  }

  Future<Result<T>> enqueue<T extends Object>(
    AgentActionQueueRequest<T> request,
  ) {
    final idempotencyKey = _idempotencyKeyFor(
      actionId: request.actionId,
      idempotencyKey: request.idempotencyKey,
    );
    if (idempotencyKey != null) {
      final existing = _idempotentResults[idempotencyKey];
      if (existing != null) {
        _metrics?.recordIdempotentReplay();
        return existing.then((result) => result.fold((value) => Success(value as T), Failure.new));
      }
    }

    final scheduled = _schedule(request);
    if (idempotencyKey != null) {
      final stored = scheduled.then<Result<Object>>(
        (result) => result.fold<Result<Object>>(Success.new, Failure.new),
      );
      _idempotentResults[idempotencyKey] = stored;
      // Evict after completion so the map does not grow without bound over the
      // lifetime of a long-running desktop agent.
      unawaited(stored.whenComplete(() => _idempotentResults.remove(idempotencyKey)));
    }

    return scheduled;
  }

  Future<Result<T>> _schedule<T extends Object>(
    AgentActionQueueRequest<T> request,
  ) {
    final policy = request.policies.queue;
    if (policy.concurrencyBehavior == AgentActionConcurrencyBehavior.allowParallel ||
        _canRunNow(request.actionId, policy)) {
      return _runNow(request);
    }

    switch (policy.concurrencyBehavior) {
      case AgentActionConcurrencyBehavior.reject:
        _metrics?.recordConcurrencyReject();
        return Future<Result<T>>.value(
          Failure(
            ActionQueueFailure.withContext(
              message: 'Action execution was rejected because the concurrency limit was reached.',
              code: AgentActionFailureCode.queueConcurrencyRejected,
              context: {
                'action_id': request.actionId,
                'reason': AgentActionQueueConstants.concurrencyLimitReachedReason,
                'user_message': 'The action is already running and the current policy rejects simultaneous executions.',
              },
            ),
          ),
        );
      case AgentActionConcurrencyBehavior.ignore:
        _metrics?.recordConcurrencyIgnore();
        return Future<Result<T>>.value(
          Failure(
            ActionQueueFailure.withContext(
              message: 'Action execution was ignored because another execution is already running.',
              code: AgentActionFailureCode.queueIgnored,
              context: {
                'action_id': request.actionId,
                'reason': AgentActionQueueConstants.concurrencyIgnoreReason,
                'user_message': 'The action is already running and this request was ignored by the configured policy.',
              },
            ),
          ),
        );
      case AgentActionConcurrencyBehavior.enqueue:
        return _enqueuePending(request);
      case AgentActionConcurrencyBehavior.allowParallel:
        return _runNow(request);
    }
  }

  Future<Result<T>> _enqueuePending<T extends Object>(
    AgentActionQueueRequest<T> request,
  ) {
    final queue = _pendingByActionId.putIfAbsent(request.actionId, Queue<_PendingActionTask<Object>>.new);
    if (queue.length >= request.policies.queue.maxQueued) {
      _metrics?.recordQueueDepthFull();
      return Future<Result<T>>.value(
        Failure(
          ActionQueueFailure.withContext(
            message: 'Action execution queue is full.',
            code: AgentActionFailureCode.queueFull,
            context: {
              'action_id': request.actionId,
              'max_queued': request.policies.queue.maxQueued,
              'reason': AgentActionQueueConstants.queueFullReason,
              'user_message': 'The action queue is full. Wait for a running execution to finish and try again.',
            },
          ),
        ),
      );
    }

    final pending = _PendingActionTask<T>(
      request: request,
      metrics: _metrics,
      onTimeout: () => _removeTimedOutPending(request.actionId),
    );
    queue.add(pending as _PendingActionTask<Object>);
    _metrics?.recordPendingEnqueued();
    _drain(request.actionId);
    return pending.future;
  }

  void _removeTimedOutPending(String actionId) {
    final queue = _pendingByActionId[actionId];
    if (queue == null) {
      return;
    }
    queue.removeWhere((pending) => pending.isCompleted);
    if (queue.isEmpty) {
      _pendingByActionId.remove(actionId);
    }
  }

  Future<Result<T>> _runNow<T extends Object>(
    AgentActionQueueRequest<T> request,
  ) async {
    _metrics?.recordRunStarted();
    _runningByActionId[request.actionId] = (_runningByActionId[request.actionId] ?? 0) + 1;
    try {
      return await request.task();
    } finally {
      final current = (_runningByActionId[request.actionId] ?? 1) - 1;
      if (current <= 0) {
        _runningByActionId.remove(request.actionId);
      } else {
        _runningByActionId[request.actionId] = current;
      }
      _drain(request.actionId);
    }
  }

  void _drain(String actionId) {
    final queue = _pendingByActionId[actionId];
    if (queue == null || queue.isEmpty) {
      return;
    }

    while (queue.isNotEmpty && _canRunNow(actionId, queue.first.request.policies.queue)) {
      final pending = queue.removeFirst();
      if (pending.isCompleted) {
        continue;
      }

      // Increment running count BEFORE starting the task so _canRunNow reflects
      // reality for subsequent loop iterations. Without this, multiple slots can
      // be granted incorrectly when maxConcurrent > 1, because _PendingActionTask
      // does not update _runningByActionId on its own.
      _runningByActionId[actionId] = (_runningByActionId[actionId] ?? 0) + 1;

      // Decrement and drain again when the dequeued task finishes (success,
      // failure, timeout, or cancellation all resolve pending.future).
      unawaited(
        pending.future.whenComplete(() {
          final current = (_runningByActionId[actionId] ?? 1) - 1;
          if (current <= 0) {
            _runningByActionId.remove(actionId);
          } else {
            _runningByActionId[actionId] = current;
          }
          _drain(actionId);
        }),
      );

      pending.start();
    }

    if (queue.isEmpty) {
      _pendingByActionId.remove(actionId);
    }
  }

  bool _canRunNow(
    String actionId,
    AgentActionQueuePolicy policy,
  ) {
    return (_runningByActionId[actionId] ?? 0) < policy.maxConcurrent;
  }

  String? _idempotencyKeyFor({
    required String actionId,
    required String? idempotencyKey,
  }) {
    final trimmed = idempotencyKey?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return '$actionId:$trimmed';
  }
}

/// Metrics for [ActionExecutionQueue]; stable counter keys for snapshots/OTel.
abstract class ActionExecutionQueueMetricsCollector {
  void recordConcurrencyReject();

  void recordConcurrencyIgnore();

  void recordQueueDepthFull();

  void recordPendingEnqueued();

  void recordIdempotentReplay();

  void recordRunStarted();

  void recordPendingWaitTimeout();

  void recordPendingCancelled();

  void recordPendingDequeueWaitTime(Duration wait);
}

class _PendingActionTask<T extends Object> {
  _PendingActionTask({
    required this.request,
    required this.metrics,
    required void Function() onTimeout,
  }) : _enqueuedAt = DateTime.now(),
       _onTimeout = onTimeout {
    _timeoutTimer = Timer(request.policies.queue.queueTimeout, _completeTimeout);
  }

  final AgentActionQueueRequest<T> request;
  final ActionExecutionQueueMetricsCollector? metrics;
  final DateTime _enqueuedAt;
  final void Function() _onTimeout;
  final Completer<Result<T>> _completer = Completer<Result<T>>();
  late final Timer _timeoutTimer;

  Future<Result<T>> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  void start() {
    if (_completer.isCompleted) {
      return;
    }
    _timeoutTimer.cancel();
    metrics?.recordPendingDequeueWaitTime(DateTime.now().difference(_enqueuedAt));
    unawaited(_run());
  }

  Future<void> _run() async {
    metrics?.recordRunStarted();
    final result = await request.task();
    if (!_completer.isCompleted) {
      _completer.complete(result);
    }
  }

  void _completeTimeout() {
    if (_completer.isCompleted) {
      return;
    }
    metrics?.recordPendingWaitTimeout();
    _completer.complete(
      Failure(
        ActionQueueFailure.withContext(
          message: 'Action execution timed out while waiting in queue.',
          code: AgentActionFailureCode.queueTimeout,
          context: {
            'action_id': request.actionId,
            'queue_timeout_ms': request.policies.queue.queueTimeout.inMilliseconds,
            'reason': AgentActionQueueConstants.queueTimeoutReason,
            'user_message': 'The action waited too long in the queue and was not started.',
          },
        ),
      ),
    );
    _onTimeout();
  }

  void cancel() {
    if (_completer.isCompleted) {
      return;
    }
    _timeoutTimer.cancel();
    metrics?.recordPendingCancelled();
    _completer.complete(
      Failure(
        ActionQueueFailure.withContext(
          message: 'Action execution was cancelled while waiting in queue.',
          code: AgentActionFailureCode.queueCancelled,
          context: {
            'action_id': request.actionId,
            'execution_id': request.executionId,
            'reason': AgentActionQueueConstants.queueCancelledReason,
            'user_message': 'Execution cancelled before starting.',
          },
        ),
      ),
    );
  }
}
