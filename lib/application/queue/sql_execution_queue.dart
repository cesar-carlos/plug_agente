import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:meta/meta.dart';
import 'package:plug_agente/application/queue/sql_execution_kind.dart';
import 'package:plug_agente/application/queue/sql_queue_lane_scheduler.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
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
    int fullRejectionLogStride = _defaultFullRejectionLogStride,
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
       _maxConcurrentBatchWorkers =
           maxConcurrentBatchWorkers ?? ConnectionConstants.sqlQueueMaxBatchWorkersForWorkers(maxConcurrentWorkers),
       _maxConcurrentLongQueryWorkers =
           maxConcurrentLongQueryWorkers ??
           ConnectionConstants.sqlQueueMaxLongQueryWorkersForWorkers(maxConcurrentWorkers),
       _maxConcurrentStreamingWorkers =
           maxConcurrentStreamingWorkers ??
           ConnectionConstants.sqlQueueMaxStreamingWorkersForWorkers(maxConcurrentWorkers),
       _maxConcurrentNonQueryWorkers =
           maxConcurrentNonQueryWorkers ??
           ConnectionConstants.sqlQueueMaxNonQueryWorkersForWorkers(maxConcurrentWorkers),
       _metricsCollector = metricsCollector,
       _defaultEnqueueTimeout = defaultEnqueueTimeout,
       _fullRejectionLogStride = fullRejectionLogStride,
       _inFlightAbortPort = inFlightAbortPort;

  /// Default stride for `queue full` rejection logs.
  ///
  /// Sustained back-pressure produces one rejection per submit attempt, which
  /// floods logs without adding new signal. We log the first rejection and
  /// then every Nth rejection while the queue stays saturated.
  static const int _defaultFullRejectionLogStride = 10;

  final int _maxQueueSize;
  final int _maxConcurrentWorkers;
  final int _maxConcurrentBatchWorkers;
  final int _maxConcurrentLongQueryWorkers;
  final int _maxConcurrentStreamingWorkers;
  final int _maxConcurrentNonQueryWorkers;
  final SqlExecutionQueueMetricsCollector? _metricsCollector;
  final Duration _defaultEnqueueTimeout;
  final int _fullRejectionLogStride;
  final ISqlInFlightExecutionAbortPort? _inFlightAbortPort;

  final Map<SqlExecutionKind, Queue<_QueuedRequest>> _queues = {
    for (final kind in SqlExecutionKind.values) kind: Queue<_QueuedRequest>(),
  };
  static const SqlQueueLaneScheduler<_QueuedRequest> _laneScheduler = SqlQueueLaneScheduler<_QueuedRequest>();
  final SqlQueueLaneSchedulerState _laneSchedulerState = SqlQueueLaneSchedulerState();
  int _queuedCount = 0;
  int _nextSequence = 0;
  int _activeWorkers = 0;
  int _activeBatchWorkers = 0;
  int _activeLongQueryWorkers = 0;
  int _activeStreamingWorkers = 0;
  int _activeNonQueryWorkers = 0;
  bool _disposed = false;
  bool _reportedSaturation70 = false;
  bool _reportedSaturation90 = false;
  Completer<void>? _drainedCompleter;
  // Consecutive `queue full` rejections without any accepted submission in
  // between. Reset whenever a submission is accepted so the next rejection
  // burst starts a fresh logging episode.
  int _consecutiveFullRejections = 0;

  /// Current number of requests waiting in the queue.
  int get queueSize => _queuedCount;

  /// Current number of workers actively executing tasks.
  int get activeWorkers => _activeWorkers;

  int get maxQueueSize => _maxQueueSize;

  int get maxConcurrentWorkers => _maxConcurrentWorkers;

  int get activeBatchWorkers => _activeBatchWorkers;

  int get maxConcurrentBatchWorkers => _maxConcurrentBatchWorkers;

  int get activeLongQueryWorkers => _activeLongQueryWorkers;

  int get maxConcurrentLongQueryWorkers => _maxConcurrentLongQueryWorkers;

  int get activeStreamingWorkers => _activeStreamingWorkers;

  int get maxConcurrentStreamingWorkers => _maxConcurrentStreamingWorkers;

  int get activeNonQueryWorkers => _activeNonQueryWorkers;

  int get maxConcurrentNonQueryWorkers => _maxConcurrentNonQueryWorkers;

  Duration get defaultEnqueueTimeout => _defaultEnqueueTimeout;

  /// Whether the queue is at capacity and will reject new requests.
  bool get isFull => _queuedCount >= _maxQueueSize;

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
    if (_disposed) {
      developer.log(
        'SQL request REJECTED (queue disposed)',
        name: 'sql_execution_queue',
        level: 900,
        error: {'request_id': requestId},
      );
      return Failure(
        _queueDisposedFailure(
          message: 'SQL execution queue is disposed',
          requestId: requestId,
        ),
      );
    }

    if (isFull) {
      _consecutiveFullRejections++;
      _metricsCollector?.recordQueueRejection();
      if (_shouldLogFullRejection(_consecutiveFullRejections)) {
        developer.log(
          'SQL request REJECTED (queue full)',
          name: 'sql_execution_queue',
          level: 900,
          error: {
            'request_id': requestId,
            'queue_size': _queuedCount,
            'max_queue_size': _maxQueueSize,
            'active_workers': _activeWorkers,
            'consecutive_full_rejections': _consecutiveFullRejections,
            'log_stride': _fullRejectionLogStride,
          },
        );
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'SQL execution queue is full; system is under heavy load',
          context: _queueBackpressureContext(
            reason: SqlPipelineContextConstants.sqlQueueFullReason,
            requestId: requestId,
          ),
        ),
      );
    }

    _consecutiveFullRejections = 0;

    final request = _QueuedRequest<T>(
      task: task,
      enqueuedAt: DateTime.now(),
      requestId: requestId,
      kind: kind,
      sequence: _nextSequence++,
      cooperativeCancellationToken: cooperativeCancellationToken,
      slotWeight: slotWeight,
    );

    _enqueue(request);
    _metricsCollector?.recordQueueAdded(_queuedCount);
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
        _completeQueueWaitTimeout(
          request: request,
          timeout: timeout,
          error: error,
          requestId: requestId,
        ),
      );
    }
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
    if (_disposed) {
      developer.log(
        'SQL request REJECTED (queue disposed)',
        name: 'sql_execution_queue',
        level: 900,
        error: {'request_id': requestId},
      );
      return Failure(
        _queueDisposedFailure(
          message: 'SQL execution queue is disposed',
          requestId: requestId,
        ),
      );
    }

    if (isFull) {
      _consecutiveFullRejections++;
      _metricsCollector?.recordQueueRejection();
      if (_shouldLogFullRejection(_consecutiveFullRejections)) {
        developer.log(
          'SQL request REJECTED (queue full)',
          name: 'sql_execution_queue',
          level: 900,
          error: {
            'request_id': requestId,
            'queue_size': _queuedCount,
            'max_queue_size': _maxQueueSize,
            'active_workers': _activeWorkers,
            'consecutive_full_rejections': _consecutiveFullRejections,
            'log_stride': _fullRejectionLogStride,
          },
        );
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'SQL execution queue is full; system is under heavy load',
          context: _queueBackpressureContext(
            reason: SqlPipelineContextConstants.sqlQueueFullReason,
            requestId: requestId,
          ),
        ),
      );
    }

    _consecutiveFullRejections = 0;

    final request = _QueuedRequest<T>.releasable(
      task: task,
      enqueuedAt: DateTime.now(),
      requestId: requestId,
      kind: kind,
      sequence: _nextSequence++,
      cooperativeCancellationToken: cooperativeCancellationToken,
      slotWeight: slotWeight,
    );

    _enqueue(request);
    _metricsCollector?.recordQueueAdded(_queuedCount);
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
        _completeQueueWaitTimeout(
          request: request,
          timeout: timeout,
          error: error,
          requestId: requestId,
        ),
      );
    }
  }

  Future<void> _processQueue() async {
    while (_activeWorkers < _maxConcurrentWorkers && _queuedCount > 0) {
      final request = _takeNextEligibleRequest();
      if (request == null) {
        return;
      }
      _metricsCollector?.recordQueueSizeChanged(_queuedCount);
      _recordQueueSaturationIfNeeded();
      if (request.isCancelled || request.completer.isCompleted) {
        continue;
      }
      request.hasStarted = true;
      request.startedAt = DateTime.now();
      if (!request.startedCompleter.isCompleted) {
        request.startedCompleter.complete();
      }
      _activeWorkers++;
      if (request.kind == SqlExecutionKind.batch) {
        _activeBatchWorkers += request.slotWeight;
      }
      if (request.kind == SqlExecutionKind.longQuery) {
        _activeLongQueryWorkers++;
      }
      if (request.kind == SqlExecutionKind.streaming) {
        _activeStreamingWorkers++;
      }
      if (request.kind == SqlExecutionKind.nonQuery) {
        _activeNonQueryWorkers++;
      }
      _metricsCollector?.recordWorkerStarted(_activeWorkers);

      unawaited(_executeTask(request));
    }
  }

  Future<void> _executeTask<T extends Object>(_QueuedRequest<T> request) async {
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

  void _releaseWorkerSlot(_QueuedRequest<dynamic> request) {
    if (request.workerSlotReleased) {
      return;
    }
    request.workerSlotReleased = true;

    if (request.kind == SqlExecutionKind.streaming) {
      final startedAt = request.startedAt;
      if (startedAt != null) {
        _metricsCollector?.recordStreamingWorkerHoldTime(
          DateTime.now().difference(startedAt),
        );
      }
    }
    _activeWorkers--;
    if (request.kind == SqlExecutionKind.batch && _activeBatchWorkers > 0) {
      _activeBatchWorkers = (_activeBatchWorkers - request.slotWeight).clamp(0, _maxConcurrentBatchWorkers);
    }
    if (request.kind == SqlExecutionKind.longQuery && _activeLongQueryWorkers > 0) {
      _activeLongQueryWorkers--;
    }
    if (request.kind == SqlExecutionKind.streaming && _activeStreamingWorkers > 0) {
      _activeStreamingWorkers--;
    }
    if (request.kind == SqlExecutionKind.nonQuery && _activeNonQueryWorkers > 0) {
      _activeNonQueryWorkers--;
    }
    _metricsCollector?.recordWorkerCompleted(_activeWorkers);
    _completeDrainedIfIdle();
    unawaited(_processQueue());
  }

  void _completeDrainedIfIdle() {
    final pending = _drainedCompleter;
    if (pending == null || pending.isCompleted) {
      return;
    }
    if (_activeWorkers == 0 && _queuedCount == 0) {
      pending.complete();
    }
  }

  _QueuedRequest? _takeNextEligibleRequest() {
    final request = _laneScheduler.takeNextEligibleRequest(
      queues: _queues,
      canStartRequest: _canStartRequest,
      roundRobinState: _laneSchedulerState,
    );
    if (request == null) {
      return null;
    }
    _queuedCount--;
    return request;
  }

  bool _canStartRequest(_QueuedRequest request) {
    return switch (request.kind) {
      SqlExecutionKind.batch => _activeBatchWorkers + request.slotWeight <= _maxConcurrentBatchWorkers,
      SqlExecutionKind.longQuery => _activeLongQueryWorkers < _maxConcurrentLongQueryWorkers,
      SqlExecutionKind.streaming => _activeStreamingWorkers < _maxConcurrentStreamingWorkers,
      SqlExecutionKind.nonQuery => _activeNonQueryWorkers < _maxConcurrentNonQueryWorkers,
      SqlExecutionKind.shortQuery || SqlExecutionKind.query => true,
    };
  }

  /// Disposes the queue and prevents new requests.
  ///
  /// Pending requests are failed immediately with [_queueDisposedFailure];
  /// in-flight workers continue to run until their tasks finish.
  void dispose() {
    _disposed = true;
    // Need to process each request with its own type
    while (_queuedCount > 0) {
      final request = _takeNextQueuedRequest();
      if (request == null) {
        break;
      }
      _metricsCollector?.recordQueueSizeChanged(_queuedCount);
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
  /// returned future completes when [_activeWorkers] reaches zero or when
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
            'active_workers': _activeWorkers,
            'queue_size': _queuedCount,
          },
        ),
      );
    }
  }

  void _completeWithDisposalFailure<T extends Object>(_QueuedRequest<T> request) {
    final failure = _queueDisposedFailure(
      message: 'SQL execution queue disposed before request could be processed',
      requestId: request.requestId,
    );
    if (!request.startedCompleter.isCompleted && !request.hasStarted) {
      request.startedCompleter.complete();
    }
    request.completeFailure(failure);
  }

  Map<String, dynamic> _queueBackpressureContext({
    required String reason,
    required String? requestId,
  }) {
    return {
      'reason': reason,
      'rpc_error_code': RpcErrorCode.rateLimited,
      'retryable': true,
      'queue_size': _queuedCount,
      'max_queue_size': _maxQueueSize,
      'active_workers': _activeWorkers,
      'max_workers': _maxConcurrentWorkers,
      'request_id': ?requestId,
      'user_message': 'O agente esta ocupado executando consultas. Aguarde alguns instantes e tente novamente.',
    };
  }

  void _recordQueueSaturationIfNeeded() {
    final saturationPercent = _queuedCount / _maxQueueSize * 100;
    _reportedSaturation70 = _recordThresholdCrossing(
      isActive: _reportedSaturation70,
      saturationPercent: saturationPercent,
      thresholdPercent: 70,
    );
    _reportedSaturation90 = _recordThresholdCrossing(
      isActive: _reportedSaturation90,
      saturationPercent: saturationPercent,
      thresholdPercent: 90,
    );
  }

  bool _shouldLogFullRejection(int rejectionCount) {
    // Log the first rejection of an episode and then every Nth rejection while
    // the queue stays saturated. The counter is reset by [submit] as soon as a
    // submission is accepted, so the next saturation burst starts fresh.
    if (rejectionCount == 1) return true;
    return rejectionCount % _fullRejectionLogStride == 0;
  }

  bool _recordThresholdCrossing({
    required bool isActive,
    required double saturationPercent,
    required int thresholdPercent,
  }) {
    if (saturationPercent < thresholdPercent) {
      return false;
    }
    if (isActive) {
      return true;
    }
    _metricsCollector?.recordQueueSaturation(
      thresholdPercent: thresholdPercent,
      currentSize: _queuedCount,
      maxSize: _maxQueueSize,
    );
    return true;
  }

  void _enqueue(_QueuedRequest request) {
    _queues[request.kind]!.addLast(request);
    _queuedCount++;
  }

  bool _removeQueuedRequest(_QueuedRequest request) {
    final removed = _queues[request.kind]!.remove(request);
    if (removed) {
      _queuedCount--;
    }
    return removed;
  }

  _QueuedRequest? _takeNextQueuedRequest() {
    final request = _laneScheduler.takeNextQueuedRequest(
      queues: _queues,
      roundRobinState: _laneSchedulerState,
    );
    if (request == null) {
      return null;
    }
    _queuedCount--;
    return request;
  }

  domain.QueryExecutionFailure _completeQueueWaitTimeout<T extends Object>({
    required _QueuedRequest<T> request,
    required Duration timeout,
    required TimeoutException error,
    required String? requestId,
  }) {
    request.isCancelled = true;
    request.cooperativeCancellationToken?.cancel();

    if (!request.hasStarted) {
      _removeQueuedRequest(request);
      _metricsCollector?.recordQueueSizeChanged(_queuedCount);
      _recordQueueSaturationIfNeeded();
    } else {
      _metricsCollector?.recordQueueTimeoutAfterWorkerStarted();
      final abortTargetId = _resolveAbortTargetId(requestId: requestId, request: request);
      if (abortTargetId != null) {
        unawaited(_inFlightAbortPort?.abortInFlightExecution(abortTargetId));
      }
      developer.log(
        'SQL request queue wait timed out after worker started; native ODBC abort requested when in-flight handle is registered',
        name: 'sql_execution_queue',
        level: 900,
        error: {
          'request_id': requestId,
          'timeout_seconds': timeout.inSeconds,
          'queue_size': _queuedCount,
          'active_workers': _activeWorkers,
          'ghost_query_risk': true,
          'cooperative_cancel_signalled': request.cooperativeCancellationToken?.isCancelled ?? false,
          'native_abort_requested': abortTargetId != null,
        },
      );
    }

    _metricsCollector?.recordQueueTimeout();
    developer.log(
      'SQL request TIMEOUT in queue',
      name: 'sql_execution_queue',
      level: 900,
      error: {
        'request_id': requestId,
        'timeout_seconds': timeout.inSeconds,
        'queue_size': _queuedCount,
        'active_workers': _activeWorkers,
        'worker_started': request.hasStarted,
        'error': error,
      },
    );

    return domain.QueryExecutionFailure.withContext(
      message: 'SQL request timed out waiting in queue',
      cause: error,
      context: {
        ..._queueBackpressureContext(
          reason: SqlPipelineContextConstants.queueWaitTimeoutReason,
          requestId: requestId,
        ),
        'timeout': true,
        'timeout_stage': 'queue',
        'timeout_seconds': timeout.inSeconds,
        'worker_started': request.hasStarted,
        if (request.hasStarted) 'ghost_query_risk': true,
      },
    );
  }

  String? _resolveAbortTargetId<T extends Object>({
    required String? requestId,
    required _QueuedRequest<T> request,
  }) {
    final normalizedRequestId = requestId?.trim();
    if (normalizedRequestId != null && normalizedRequestId.isNotEmpty) {
      return normalizedRequestId;
    }
    final queuedRequestId = request.requestId?.trim();
    if (queuedRequestId != null && queuedRequestId.isNotEmpty) {
      return queuedRequestId;
    }
    return null;
  }

  /// Test hook for queue-wait timeout after worker start (ghost-query path).
  @visibleForTesting
  domain.QueryExecutionFailure recordQueueWaitTimeoutForTesting({
    required bool workerStarted,
    CancellationToken? cooperativeCancellationToken,
    String? requestId,
  }) {
    final request = _QueuedRequest<int>(
      task: () async => const Success(0),
      enqueuedAt: DateTime.now(),
      requestId: requestId,
      kind: SqlExecutionKind.query,
      sequence: -1,
      cooperativeCancellationToken: cooperativeCancellationToken,
    )..hasStarted = workerStarted;

    return _completeQueueWaitTimeout(
      request: request,
      timeout: const Duration(milliseconds: 1),
      error: TimeoutException('queue wait timeout (test)'),
      requestId: requestId,
    );
  }

  domain.ConfigurationFailure _queueDisposedFailure({
    required String message,
    required String? requestId,
  }) {
    return domain.ConfigurationFailure.withContext(
      message: message,
      context: {
        'reason': SqlPipelineContextConstants.queueDisposedReason,
        'request_id': ?requestId,
        'user_message': 'A fila de execucao SQL foi encerrada. Reconecte o agente e tente novamente.',
      },
    );
  }
}

class _QueuedRequest<T extends Object> {
  _QueuedRequest({
    required this.task,
    required this.enqueuedAt,
    required this.kind,
    required this.sequence,
    this.requestId,
    this.cooperativeCancellationToken,
    this.slotWeight = 1,
  }) : releasableTask = null;

  _QueuedRequest.releasable({
    required Future<Result<T>> Function(void Function() releaseWorker) task,
    required this.enqueuedAt,
    required this.kind,
    required this.sequence,
    this.requestId,
    this.cooperativeCancellationToken,
    this.slotWeight = 1,
  }) : task = null,
       releasableTask = task;

  final Future<Result<T>> Function()? task;
  final Future<Result<T>> Function(void Function() releaseWorker)? releasableTask;
  final CancellationToken? cooperativeCancellationToken;
  final DateTime enqueuedAt;
  final SqlExecutionKind kind;
  final int sequence;
  final int slotWeight;
  final String? requestId;
  bool hasStarted = false;
  bool isCancelled = false;
  bool workerSlotReleased = false;
  DateTime? startedAt;
  final Completer<void> startedCompleter = Completer<void>();
  final Completer<Result<T>> completer = Completer<Result<T>>();

  void completeFailure(Exception failure) {
    if (!completer.isCompleted) {
      completer.complete(Failure<T, Exception>(failure));
    }
  }
}
