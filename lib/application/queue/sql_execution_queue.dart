import 'dart:async';
import 'dart:developer' as developer;

import 'package:meta/meta.dart';
import 'package:plug_agente/application/queue/sql_execution/sql_execution_backpressure.dart';
import 'package:plug_agente/application/queue/sql_execution/sql_execution_ghost_query_policy.dart';
import 'package:plug_agente/application/queue/sql_execution/sql_execution_lane_capacity.dart';
import 'package:plug_agente/application/queue/sql_execution/sql_execution_lane_registry.dart';
import 'package:plug_agente/application/queue/sql_execution/sql_execution_queue_saturation.dart';
import 'package:plug_agente/application/queue/sql_execution/sql_execution_queued_request.dart';
import 'package:plug_agente/application/queue/sql_execution_kind.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

export 'package:plug_agente/application/queue/sql_execution_kind.dart';

/// Bounded FIFO queue for SQL execution requests to prevent pool overload.
///
/// Enforces backpressure by rejecting requests when the queue is full,
/// returning a clear failure instead of cascading timeouts.
///
/// `enqueueTimeout` / `defaultEnqueueTimeout` only bounds **queue-wait** time
/// (until a worker slot is acquired). Once the worker-start signal completes, the
/// caller waits for task completion without a queue-level deadline.
///
/// When a queue-wait timeout races with worker start, the caller receives a
/// queue-timeout failure but ODBC work may already be running ("ghost query").
/// The queue cannot safely abort arbitrary ODBC tasks from here:
/// cancellation requires cooperative cancellation-token wiring in the task
/// (materialized sql.execute and streaming) or ODBC-layer execution timeouts
/// when no token is observed cooperatively.
/// See ConnectionConstants.sqlQueueEnqueueTimeout for the timeout policy.
///
/// Usage:
/// ```dart
/// final queue = SqlExecutionQueue(
///   maxQueueSize: 500,
///   maxConcurrentWorkers: 4,
///   metricsCollector: metrics,
/// );
///
/// final result = await queue.submit(() async {
///   return await gateway.executeQuery(request);
/// });
/// ```
class SqlExecutionQueue {
  SqlExecutionQueue({
    required int maxQueueSize,
    required int maxConcurrentWorkers,
    int? maxConcurrentBatchWorkers,
    int? maxConcurrentLongQueryWorkers,
    int? maxConcurrentStreamingWorkers,
    int? maxConcurrentNonQueryWorkers,
    SqlExecutionQueueMetricsCollector? metricsCollector,
    Duration defaultEnqueueTimeout = const Duration(seconds: 5),
    int fullRejectionLogStride = SqlExecutionBackpressure.defaultFullRejectionLogStride,
    ISqlInFlightExecutionAbortPort? inFlightAbortPort,
  }) : assert(maxQueueSize > 0, 'maxQueueSize must be > 0'),
       assert(maxConcurrentWorkers > 0, 'maxConcurrentWorkers must be > 0'),
       assert(
         maxConcurrentBatchWorkers == null || maxConcurrentBatchWorkers > 0,
         'maxConcurrentBatchWorkers must be null or > 0',
       ),
       assert(
         maxConcurrentLongQueryWorkers == null || maxConcurrentLongQueryWorkers > 0,
         'maxConcurrentLongQueryWorkers must be null or > 0',
       ),
       assert(
         maxConcurrentStreamingWorkers == null || maxConcurrentStreamingWorkers > 0,
         'maxConcurrentStreamingWorkers must be null or > 0',
       ),
       assert(
         maxConcurrentNonQueryWorkers == null || maxConcurrentNonQueryWorkers > 0,
         'maxConcurrentNonQueryWorkers must be null or > 0',
       ),
       assert(
         fullRejectionLogStride > 0,
         'fullRejectionLogStride must be greater than zero',
       ),
       _maxQueueSize = maxQueueSize,
       _maxConcurrentWorkers = maxConcurrentWorkers,
       _laneCapacity = SqlExecutionLaneCapacity(
         maxConcurrentWorkers: maxConcurrentWorkers,
         maxConcurrentBatchWorkers:
             maxConcurrentBatchWorkers ?? ConnectionConstants.sqlQueueMaxBatchWorkersForWorkers(maxConcurrentWorkers),
         maxConcurrentLongQueryWorkers:
             maxConcurrentLongQueryWorkers ??
             ConnectionConstants.sqlQueueMaxLongQueryWorkersForWorkers(maxConcurrentWorkers),
         maxConcurrentStreamingWorkers:
             maxConcurrentStreamingWorkers ??
             ConnectionConstants.sqlQueueMaxStreamingWorkersForWorkers(maxConcurrentWorkers),
         maxConcurrentNonQueryWorkers:
             maxConcurrentNonQueryWorkers ??
             ConnectionConstants.sqlQueueMaxNonQueryWorkersForWorkers(maxConcurrentWorkers),
       ),
       _metricsCollector = metricsCollector,
       _defaultEnqueueTimeout = defaultEnqueueTimeout,
       _fullRejectionLogStride = fullRejectionLogStride,
       _saturationTracker = SqlExecutionQueueSaturationTracker() {
    _ghostQueryPolicy = SqlExecutionGhostQueryPolicy(
      inFlightAbortPort: inFlightAbortPort,
      metricsCollector: metricsCollector,
      saturationTracker: _saturationTracker,
      maxQueueSize: maxQueueSize,
      maxConcurrentWorkers: maxConcurrentWorkers,
    );
  }

  final int _maxQueueSize;
  final int _maxConcurrentWorkers;
  final SqlExecutionLaneCapacity _laneCapacity;
  final SqlExecutionLaneRegistry _laneRegistry = SqlExecutionLaneRegistry();
  final SqlExecutionQueueMetricsCollector? _metricsCollector;
  final Duration _defaultEnqueueTimeout;
  final int _fullRejectionLogStride;
  final SqlExecutionQueueSaturationTracker _saturationTracker;
  late final SqlExecutionGhostQueryPolicy _ghostQueryPolicy;

  bool _disposed = false;
  Completer<void>? _drainedCompleter;
  // Consecutive `queue full` rejections without any accepted submission in
  // between. Reset whenever a submission is accepted so the next rejection
  // burst starts a fresh logging episode.
  int _consecutiveFullRejections = 0;

  /// Current number of requests waiting in the queue.
  int get queueSize => _laneRegistry.queuedCount;

  /// Current number of workers actively executing tasks.
  int get activeWorkers => _laneCapacity.activeWorkers;

  int get maxQueueSize => _maxQueueSize;

  int get maxConcurrentWorkers => _maxConcurrentWorkers;

  int get activeBatchWorkers => _laneCapacity.activeBatchWorkers;

  int get maxConcurrentBatchWorkers => _laneCapacity.maxConcurrentBatchWorkers;

  int get activeLongQueryWorkers => _laneCapacity.activeLongQueryWorkers;

  int get maxConcurrentLongQueryWorkers => _laneCapacity.maxConcurrentLongQueryWorkers;

  int get activeStreamingWorkers => _laneCapacity.activeStreamingWorkers;

  int get maxConcurrentStreamingWorkers => _laneCapacity.maxConcurrentStreamingWorkers;

  int get activeNonQueryWorkers => _laneCapacity.activeNonQueryWorkers;

  int get maxConcurrentNonQueryWorkers => _laneCapacity.maxConcurrentNonQueryWorkers;

  Duration get defaultEnqueueTimeout => _defaultEnqueueTimeout;

  /// Whether the queue is at capacity and will reject new requests.
  bool get isFull => _laneRegistry.queuedCount >= _maxQueueSize;

  /// Number of consecutive `queue full` rejections in the current saturation
  /// episode. Resets to zero whenever a submission is accepted.
  int get consecutiveFullRejections => _consecutiveFullRejections;

  /// Submits a SQL execution task to the queue.
  ///
  /// Returns [Result<T>] containing either:
  /// - Success(T): Task completed successfully
  /// - Failure(ConfigurationFailure): Queue is full (immediate rejection)
  /// - Failure(QueryExecutionFailure): Task timed out in queue
  /// - Failure: Task failed during execution (from the task itself)
  ///
  /// The [enqueueTimeout] controls how long a request can wait in the queue
  /// before being considered timed out. Default is 5 seconds.
  Future<Result<T>> submit<T extends Object>(
    Future<Result<T>> Function() task, {
    Duration? enqueueTimeout,
    String? requestId,
    SqlExecutionKind kind = SqlExecutionKind.query,
    CancellationToken? cooperativeCancellationToken,
    int slotWeight = 1,
  }) async {
    final admission = _admitSubmission(requestId: requestId);
    if (admission != null) {
      return Failure(admission);
    }

    final request = SqlExecutionQueuedRequest<T>(
      task: task,
      enqueuedAt: DateTime.now(),
      requestId: requestId,
      kind: kind,
      sequence: _laneRegistry.nextSequence++,
      cooperativeCancellationToken: cooperativeCancellationToken,
      slotWeight: slotWeight,
    );

    return _runSubmittedRequest(
      request: request,
      enqueueTimeout: enqueueTimeout,
      requestId: requestId,
    );
  }

  /// Submits a task that can release its queue worker slot before finishing.
  ///
  /// The task receives a release-worker callback; invoking it frees the worker for other
  /// queued requests while the task continues running. Used by streaming so
  /// ODBC connect/setup is bounded by the queue but the stream body runs under
  /// the direct ODBC connection limiter only.
  Future<Result<T>> submitWithReleasableWorker<T extends Object>(
    Future<Result<T>> Function(void Function() releaseWorker) task, {
    Duration? enqueueTimeout,
    String? requestId,
    SqlExecutionKind kind = SqlExecutionKind.query,
    CancellationToken? cooperativeCancellationToken,
    int slotWeight = 1,
  }) async {
    final admission = _admitSubmission(requestId: requestId);
    if (admission != null) {
      return Failure(admission);
    }

    final request = SqlExecutionQueuedRequest<T>.releasable(
      task: task,
      enqueuedAt: DateTime.now(),
      requestId: requestId,
      kind: kind,
      sequence: _laneRegistry.nextSequence++,
      cooperativeCancellationToken: cooperativeCancellationToken,
      slotWeight: slotWeight,
    );

    return _runSubmittedRequest(
      request: request,
      enqueueTimeout: enqueueTimeout,
      requestId: requestId,
    );
  }

  domain.ConfigurationFailure? _admitSubmission({required String? requestId}) {
    if (_disposed) {
      developer.log(
        'SQL request REJECTED (queue disposed)',
        name: 'sql_execution_queue',
        level: 900,
        error: {'request_id': requestId},
      );
      return SqlExecutionBackpressure.queueDisposedFailure(
        message: 'SQL execution queue is disposed',
        requestId: requestId,
      );
    }

    if (isFull) {
      _consecutiveFullRejections++;
      _metricsCollector?.recordQueueRejection();
      if (SqlExecutionBackpressure.shouldLogFullRejection(
        rejectionCount: _consecutiveFullRejections,
        logStride: _fullRejectionLogStride,
      )) {
        developer.log(
          'SQL request REJECTED (queue full)',
          name: 'sql_execution_queue',
          level: 900,
          error: {
            'request_id': requestId,
            'queue_size': _laneRegistry.queuedCount,
            'max_queue_size': _maxQueueSize,
            'active_workers': _laneCapacity.activeWorkers,
            'consecutive_full_rejections': _consecutiveFullRejections,
            'log_stride': _fullRejectionLogStride,
          },
        );
      }
      return SqlExecutionBackpressure.queueFullFailure(
        requestId: requestId,
        queueSize: _laneRegistry.queuedCount,
        maxQueueSize: _maxQueueSize,
        activeWorkers: _laneCapacity.activeWorkers,
        maxWorkers: _maxConcurrentWorkers,
      );
    }

    _consecutiveFullRejections = 0;
    return null;
  }

  Future<Result<T>> _runSubmittedRequest<T extends Object>({
    required SqlExecutionQueuedRequest<T> request,
    required Duration? enqueueTimeout,
    required String? requestId,
  }) async {
    _laneRegistry.enqueue(request);
    _metricsCollector?.recordQueueAdded(_laneRegistry.queuedCount);
    _recordQueueSaturationIfNeeded();

    unawaited(_processQueue());

    final timeout = enqueueTimeout ?? _defaultEnqueueTimeout;
    try {
      await request.startedCompleter.future.timeout(timeout);

      final result = await request.completer.future;
      final waitTime = (request.startedAt ?? DateTime.now()).difference(
        request.enqueuedAt,
      );
      _metricsCollector?.recordQueueWaitTime(waitTime);

      return result;
    } on TimeoutException catch (error) {
      return Failure(
        _ghostQueryPolicy.completeQueueWaitTimeout(
          request: request,
          timeout: timeout,
          error: error,
          requestId: requestId,
          queueSize: () => _laneRegistry.queuedCount,
          activeWorkers: () => _laneCapacity.activeWorkers,
          removeQueuedRequest: _laneRegistry.remove,
        ),
      );
    }
  }

  Future<void> _processQueue() async {
    while (_laneCapacity.hasAvailableWorkerSlot() && _laneRegistry.queuedCount > 0) {
      final request = _laneRegistry.takeNextEligible(_laneCapacity.canStart);
      if (request == null) {
        return;
      }
      _metricsCollector?.recordQueueSizeChanged(_laneRegistry.queuedCount);
      _recordQueueSaturationIfNeeded();
      if (request.isCancelled || request.completer.isCompleted) {
        continue;
      }
      request.hasStarted = true;
      request.startedAt = DateTime.now();
      if (!request.startedCompleter.isCompleted) {
        request.startedCompleter.complete();
      }
      _laneCapacity.onWorkerStarted(request, metricsCollector: _metricsCollector);

      unawaited(_executeTask(request));
    }
  }

  Future<void> _executeTask<T extends Object>(SqlExecutionQueuedRequest<T> request) async {
    if (request.isCancelled) {
      return;
    }

    try {
      final Future<Result<T>> resultFuture;
      if (request.releasableTask != null) {
        resultFuture = request.releasableTask!(
          () => _releaseWorkerSlot(request),
        );
      } else {
        resultFuture = request.task!();
      }
      final result = await resultFuture;
      if (!request.completer.isCompleted && !request.isCancelled) {
        request.completer.complete(result);
      }
    } on Object catch (error, stackTrace) {
      developer.log(
        'SQL execution task threw unexpected error',
        name: 'sql_execution_queue',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      if (!request.completer.isCompleted) {
        final failure = domain.ServerFailure.withContext(
          message: 'SQL execution task failed with unexpected error',
          cause: error is Exception ? error : null,
          context: {
            'reason': SqlPipelineContextConstants.unexpectedTaskErrorReason,
            'request_id': ?request.requestId,
          },
        );
        request.completeFailure(failure);
      }
    } finally {
      _releaseWorkerSlot(request);
    }
  }

  void _releaseWorkerSlot(SqlExecutionQueuedRequest<Object> request) {
    if (request.workerSlotReleased) {
      return;
    }
    request.workerSlotReleased = true;

    _laneCapacity.onWorkerReleased(request, metricsCollector: _metricsCollector);
    _completeDrainedIfIdle();
    unawaited(_processQueue());
  }

  void _completeDrainedIfIdle() {
    final pending = _drainedCompleter;
    if (pending == null || pending.isCompleted) {
      return;
    }
    if (_laneCapacity.activeWorkers == 0 && _laneRegistry.queuedCount == 0) {
      pending.complete();
    }
  }

  /// Disposes the queue and prevents new requests.
  ///
  /// Pending requests are failed immediately with a disposed failure;
  /// in-flight workers continue to run until their tasks finish.
  void dispose() {
    _disposed = true;
    while (_laneRegistry.queuedCount > 0) {
      final request = _laneRegistry.takeNextQueued();
      if (request == null) {
        break;
      }
      _metricsCollector?.recordQueueSizeChanged(_laneRegistry.queuedCount);
      _recordQueueSaturationIfNeeded();
      if (!request.completer.isCompleted) {
        _completeWithDisposalFailure(request);
      }
    }
    _completeDrainedIfIdle();
  }

  /// Prevents new requests and waits for in-flight workers to finish.
  ///
  /// Pending requests are failed immediately (same semantics as [dispose]); the
  /// returned future completes when active workers reach zero or when
  /// [timeout] elapses. Use this on shutdown to release ODBC connections
  /// instead of returning while workers still hold them.
  Future<Result<void>> disposeGracefully({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = _drainedCompleter ??= Completer<void>();
    dispose();
    if (completer.isCompleted) {
      return const Success(unit);
    }
    try {
      await completer.future.timeout(timeout);
      return const Success(unit);
    } on TimeoutException catch (error) {
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution queue did not drain within ${timeout.inSeconds}s',
          cause: error,
          context: {
            'reason': SqlPipelineContextConstants.queueDisposedReason,
            'timeout': true,
            'timeout_stage': 'shutdown',
            'timeout_seconds': timeout.inSeconds,
            'active_workers': _laneCapacity.activeWorkers,
            'queue_size': _laneRegistry.queuedCount,
          },
        ),
      );
    }
  }

  void _completeWithDisposalFailure<T extends Object>(SqlExecutionQueuedRequest<T> request) {
    final failure = SqlExecutionBackpressure.queueDisposedFailure(
      message: 'SQL execution queue disposed before request could be processed',
      requestId: request.requestId,
    );
    if (!request.startedCompleter.isCompleted && !request.hasStarted) {
      request.startedCompleter.complete();
    }
    request.completeFailure(failure);
  }

  void _recordQueueSaturationIfNeeded() {
    _saturationTracker.recordIfNeeded(
      queuedCount: _laneRegistry.queuedCount,
      maxQueueSize: _maxQueueSize,
      metricsCollector: _metricsCollector,
    );
  }

  /// Test hook for queue-wait timeout after worker start (ghost-query path).
  @visibleForTesting
  domain.QueryExecutionFailure recordQueueWaitTimeoutForTesting({
    required bool workerStarted,
    CancellationToken? cooperativeCancellationToken,
    String? requestId,
  }) {
    final request = SqlExecutionQueuedRequest<int>(
      task: () async => const Success(0),
      enqueuedAt: DateTime.now(),
      requestId: requestId,
      kind: SqlExecutionKind.query,
      sequence: -1,
      cooperativeCancellationToken: cooperativeCancellationToken,
    )..hasStarted = workerStarted;

    return _ghostQueryPolicy.completeQueueWaitTimeout(
      request: request,
      timeout: const Duration(milliseconds: 1),
      error: TimeoutException('queue wait timeout (test)'),
      requestId: requestId,
      queueSize: () => _laneRegistry.queuedCount,
      activeWorkers: () => _laneCapacity.activeWorkers,
      removeQueuedRequest: _laneRegistry.remove,
    );
  }
}
