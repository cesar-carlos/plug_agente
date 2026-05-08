import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:result_dart/result_dart.dart';

/// Bounded FIFO queue for SQL execution requests to prevent pool overload.
///
/// Enforces backpressure by rejecting requests when the queue is full,
/// returning a clear failure instead of cascading timeouts.
///
/// Usage:
/// ```dart
/// final queue = SqlExecutionQueue(
///   maxQueueSize: 50,
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
    SqlExecutionQueueMetricsCollector? metricsCollector,
    Duration defaultEnqueueTimeout = const Duration(seconds: 5),
  }) : assert(maxQueueSize > 0, 'maxQueueSize must be > 0'),
       assert(maxConcurrentWorkers > 0, 'maxConcurrentWorkers must be > 0'),
       _maxQueueSize = maxQueueSize,
       _maxConcurrentWorkers = maxConcurrentWorkers,
       _metricsCollector = metricsCollector,
       _defaultEnqueueTimeout = defaultEnqueueTimeout;

  final int _maxQueueSize;
  final int _maxConcurrentWorkers;
  final SqlExecutionQueueMetricsCollector? _metricsCollector;
  final Duration _defaultEnqueueTimeout;

  final Queue<_QueuedRequest> _queue = Queue<_QueuedRequest>();
  int _activeWorkers = 0;
  bool _disposed = false;

  /// Current number of requests waiting in the queue.
  int get queueSize => _queue.length;

  /// Current number of workers actively executing tasks.
  int get activeWorkers => _activeWorkers;

  /// Whether the queue is at capacity and will reject new requests.
  bool get isFull => _queue.length >= _maxQueueSize;

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
  }) async {
    developer.log(
      'SQL request submitted',
      name: 'sql_execution_queue',
      level: 500,
      error: {'request_id': requestId, 'queue_size': _queue.length, 'active_workers': _activeWorkers},
    );

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
      _metricsCollector?.recordQueueRejection();
      developer.log(
        'SQL request REJECTED (queue full)',
        name: 'sql_execution_queue',
        level: 900,
        error: {
          'request_id': requestId,
          'queue_size': _queue.length,
          'max_queue_size': _maxQueueSize,
          'active_workers': _activeWorkers,
        },
      );
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'SQL execution queue is full; system is under heavy load',
          context: _queueBackpressureContext(
            reason: 'sql_queue_full',
            requestId: requestId,
          ),
        ),
      );
    }

    final request = _QueuedRequest<T>(
      task: task,
      enqueuedAt: DateTime.now(),
      requestId: requestId,
    );

    _queue.addLast(request);
    _metricsCollector?.recordQueueAdded(_queue.length);

    unawaited(_processQueue());

    final timeout = enqueueTimeout ?? _defaultEnqueueTimeout;
    try {
      await request.startedCompleter.future.timeout(timeout);

      final result = await request.completer.future;
      final waitTime = (request.startedAt ?? DateTime.now()).difference(
        request.enqueuedAt,
      );
      _metricsCollector?.recordQueueWaitTime(waitTime);

      developer.log(
        'SQL request completed',
        name: 'sql_execution_queue',
        level: 500,
        error: {
          'request_id': requestId,
          'wait_time_ms': waitTime.inMilliseconds,
          'result': result.isSuccess() ? 'success' : 'failure',
        },
      );

      return result;
    } on TimeoutException catch (error) {
      request.isCancelled = true;
      if (!request.hasStarted) {
        _queue.remove(request);
        _metricsCollector?.recordQueueSizeChanged(_queue.length);
      }
      _metricsCollector?.recordQueueTimeout();
      developer.log(
        'SQL request TIMEOUT in queue',
        name: 'sql_execution_queue',
        level: 900,
        error: {
          'request_id': requestId,
          'timeout_seconds': timeout.inSeconds,
          'queue_size': _queue.length,
          'active_workers': _activeWorkers,
          'error': error,
        },
      );
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL request timed out waiting in queue',
          cause: error,
          context: {
            ..._queueBackpressureContext(
              reason: 'queue_wait_timeout',
              requestId: requestId,
            ),
            'timeout': true,
            'timeout_stage': 'queue',
            'timeout_seconds': timeout.inSeconds,
          },
        ),
      );
    }
  }

  Future<void> _processQueue() async {
    while (_activeWorkers < _maxConcurrentWorkers && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      _metricsCollector?.recordQueueSizeChanged(_queue.length);
      if (request.isCancelled || request.completer.isCompleted) {
        continue;
      }
      request.hasStarted = true;
      request.startedAt = DateTime.now();
      if (!request.startedCompleter.isCompleted) {
        request.startedCompleter.complete();
      }
      _activeWorkers++;
      _metricsCollector?.recordWorkerStarted(_activeWorkers);

      unawaited(_executeTask(request));
    }
  }

  Future<void> _executeTask<T extends Object>(_QueuedRequest<T> request) async {
    try {
      final result = await request.task();
      if (!request.completer.isCompleted) {
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
            'reason': 'unexpected_task_error',
            'request_id': ?request.requestId,
          },
        );
        request.completeFailure(failure);
      }
    } finally {
      _activeWorkers--;
      _metricsCollector?.recordWorkerCompleted(_activeWorkers);
      unawaited(_processQueue());
    }
  }

  /// Disposes the queue and prevents new requests.
  void dispose() {
    _disposed = true;
    // Need to process each request with its own type
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      _metricsCollector?.recordQueueSizeChanged(_queue.length);
      if (!request.completer.isCompleted) {
        _completeWithDisposalFailure(request);
      }
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
      'queue_size': _queue.length,
      'max_queue_size': _maxQueueSize,
      'active_workers': _activeWorkers,
      'max_workers': _maxConcurrentWorkers,
      'request_id': ?requestId,
      'user_message': 'O agente esta ocupado executando consultas. Aguarde alguns instantes e tente novamente.',
    };
  }

  domain.ConfigurationFailure _queueDisposedFailure({
    required String message,
    required String? requestId,
  }) {
    return domain.ConfigurationFailure.withContext(
      message: message,
      context: {
        'reason': 'queue_disposed',
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
    this.requestId,
  });

  final Future<Result<T>> Function() task;
  final DateTime enqueuedAt;
  final String? requestId;
  bool hasStarted = false;
  bool isCancelled = false;
  DateTime? startedAt;
  final Completer<void> startedCompleter = Completer<void>();
  final Completer<Result<T>> completer = Completer<Result<T>>();

  void completeFailure(Exception failure) {
    if (!completer.isCompleted) {
      completer.complete(Failure<T, Exception>(failure));
    }
  }
}

/// Metrics collector interface for SQL execution queue.
abstract class SqlExecutionQueueMetricsCollector {
  void recordQueueAdded(int currentSize);
  void recordQueueSizeChanged(int currentSize);
  void recordQueueRejection();
  void recordQueueTimeout();
  void recordQueueWaitTime(Duration waitTime);
  void recordWorkerStarted(int activeCount);
  void recordWorkerCompleted(int activeCount);
}
