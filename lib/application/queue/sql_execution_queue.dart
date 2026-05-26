import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
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
    int? maxConcurrentBatchWorkers,
    int? maxConcurrentLongQueryWorkers,
    int? maxConcurrentNonQueryWorkers,
    SqlExecutionQueueMetricsCollector? metricsCollector,
    Duration defaultEnqueueTimeout = const Duration(seconds: 5),
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
         maxConcurrentNonQueryWorkers == null || maxConcurrentNonQueryWorkers > 0,
         'maxConcurrentNonQueryWorkers must be null or > 0',
       ),
       _maxQueueSize = maxQueueSize,
       _maxConcurrentWorkers = maxConcurrentWorkers,
       _maxConcurrentBatchWorkers = maxConcurrentBatchWorkers ?? max(1, maxConcurrentWorkers ~/ 2),
       _maxConcurrentLongQueryWorkers = maxConcurrentLongQueryWorkers ?? max(1, maxConcurrentWorkers ~/ 2),
       _maxConcurrentNonQueryWorkers = maxConcurrentNonQueryWorkers ?? max(1, maxConcurrentWorkers ~/ 2),
       _metricsCollector = metricsCollector,
       _defaultEnqueueTimeout = defaultEnqueueTimeout;

  final int _maxQueueSize;
  final int _maxConcurrentWorkers;
  final int _maxConcurrentBatchWorkers;
  final int _maxConcurrentLongQueryWorkers;
  final int _maxConcurrentNonQueryWorkers;
  final SqlExecutionQueueMetricsCollector? _metricsCollector;
  final Duration _defaultEnqueueTimeout;

  final Map<SqlExecutionKind, Queue<_QueuedRequest>> _queues = {
    for (final kind in SqlExecutionKind.values) kind: Queue<_QueuedRequest>(),
  };
  int _queuedCount = 0;
  int _nextSequence = 0;
  int _activeWorkers = 0;
  int _activeBatchWorkers = 0;
  int _activeLongQueryWorkers = 0;
  int _activeNonQueryWorkers = 0;
  bool _disposed = false;
  bool _reportedSaturation70 = false;
  bool _reportedSaturation90 = false;

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

  int get activeNonQueryWorkers => _activeNonQueryWorkers;

  int get maxConcurrentNonQueryWorkers => _maxConcurrentNonQueryWorkers;

  Duration get defaultEnqueueTimeout => _defaultEnqueueTimeout;

  /// Whether the queue is at capacity and will reject new requests.
  bool get isFull => _queuedCount >= _maxQueueSize;

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
  }) async {
    developer.log(
      'SQL request submitted',
      name: 'sql_execution_queue',
      level: 500,
      error: {'request_id': requestId, 'queue_size': _queuedCount, 'active_workers': _activeWorkers},
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
          'queue_size': _queuedCount,
          'max_queue_size': _maxQueueSize,
          'active_workers': _activeWorkers,
        },
      );
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

    final request = _QueuedRequest<T>(
      task: task,
      enqueuedAt: DateTime.now(),
      requestId: requestId,
      kind: kind,
      sequence: _nextSequence++,
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
        _removeQueuedRequest(request);
        _metricsCollector?.recordQueueSizeChanged(_queuedCount);
        _recordQueueSaturationIfNeeded();
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
          'error': error,
        },
      );
      return Failure(
        domain.QueryExecutionFailure.withContext(
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
          },
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
        _activeBatchWorkers++;
      }
      if (request.kind == SqlExecutionKind.longQuery) {
        _activeLongQueryWorkers++;
      }
      if (request.kind == SqlExecutionKind.nonQuery) {
        _activeNonQueryWorkers++;
      }
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
            'reason': SqlPipelineContextConstants.unexpectedTaskErrorReason,
            'request_id': ?request.requestId,
          },
        );
        request.completeFailure(failure);
      }
    } finally {
      _activeWorkers--;
      if (request.kind == SqlExecutionKind.batch && _activeBatchWorkers > 0) {
        _activeBatchWorkers--;
      }
      if (request.kind == SqlExecutionKind.longQuery && _activeLongQueryWorkers > 0) {
        _activeLongQueryWorkers--;
      }
      if (request.kind == SqlExecutionKind.nonQuery && _activeNonQueryWorkers > 0) {
        _activeNonQueryWorkers--;
      }
      _metricsCollector?.recordWorkerCompleted(_activeWorkers);
      unawaited(_processQueue());
    }
  }

  _QueuedRequest? _takeNextEligibleRequest() {
    MapEntry<SqlExecutionKind, Queue<_QueuedRequest>>? selected;
    for (final entry in _queues.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final candidate = entry.value.first;
      if (!_canStartRequest(candidate)) {
        continue;
      }
      final current = selected;
      if (current == null || candidate.sequence < current.value.first.sequence) {
        selected = entry;
      }
    }

    if (selected == null) {
      return null;
    }
    _queuedCount--;
    return selected.value.removeFirst();
  }

  bool _canStartRequest(_QueuedRequest request) {
    return switch (request.kind) {
      SqlExecutionKind.batch => _activeBatchWorkers < _maxConcurrentBatchWorkers,
      SqlExecutionKind.longQuery => _activeLongQueryWorkers < _maxConcurrentLongQueryWorkers,
      SqlExecutionKind.nonQuery => _activeNonQueryWorkers < _maxConcurrentNonQueryWorkers,
      SqlExecutionKind.shortQuery || SqlExecutionKind.query => true,
    };
  }

  /// Disposes the queue and prevents new requests.
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
    MapEntry<SqlExecutionKind, Queue<_QueuedRequest>>? selected;
    for (final entry in _queues.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final current = selected;
      if (current == null || entry.value.first.sequence < current.value.first.sequence) {
        selected = entry;
      }
    }
    if (selected == null) {
      return null;
    }
    _queuedCount--;
    return selected.value.removeFirst();
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
  });

  final Future<Result<T>> Function() task;
  final DateTime enqueuedAt;
  final SqlExecutionKind kind;
  final int sequence;
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

enum SqlExecutionKind {
  /// Generic kind — treated identically to `shortQuery`. Used as the default
  /// for callers that do not classify the request (e.g. direct
  /// [SqlExecutionQueue.submit] calls outside `QueuedDatabaseGateway`).
  query,
  shortQuery,
  longQuery,
  nonQuery,
  batch,
}

/// Metrics collector interface for SQL execution queue.
abstract class SqlExecutionQueueMetricsCollector {
  void recordQueueAdded(int currentSize);
  void recordQueueSizeChanged(int currentSize);
  void recordQueueRejection();
  void recordQueueTimeout();
  void recordQueueSaturation({
    required int thresholdPercent,
    required int currentSize,
    required int maxSize,
  });
  void recordQueueWaitTime(Duration waitTime);
  void recordWorkerStarted(int activeCount);
  void recordWorkerCompleted(int activeCount);
}
