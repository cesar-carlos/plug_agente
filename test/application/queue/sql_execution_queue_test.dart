import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';
import 'package:result_dart/result_dart.dart' as res;

class _MockInFlightAbortPort extends Mock implements ISqlInFlightExecutionAbortPort {}

class _MockMetricsCollector implements SqlExecutionQueueMetricsCollector {
  int queueAddedCount = 0;
  int queueRejectionCount = 0;
  int queueTimeoutCount = 0;
  int queueTimeoutAfterWorkerStartedCount = 0;
  int workerStartedCount = 0;
  int workerCompletedCount = 0;
  final List<int> saturationThresholds = [];
  final List<Duration> waitTimes = [];
  final List<int> queueSizes = [];
  final List<int> workerCounts = [];
  final List<Duration> streamingWorkerHoldTimes = [];

  @override
  void recordQueueAdded(int currentSize) {
    queueAddedCount++;
    queueSizes.add(currentSize);
  }

  @override
  void recordQueueSizeChanged(int currentSize) {
    queueSizes.add(currentSize);
  }

  @override
  void recordQueueRejection() {
    queueRejectionCount++;
  }

  @override
  void recordQueueTimeout() {
    queueTimeoutCount++;
  }

  @override
  void recordQueueTimeoutAfterWorkerStarted() {
    queueTimeoutAfterWorkerStartedCount++;
  }

  @override
  void recordQueueSaturation({
    required int thresholdPercent,
    required int currentSize,
    required int maxSize,
  }) {
    saturationThresholds.add(thresholdPercent);
  }

  @override
  void recordQueueWaitTime(Duration waitTime) {
    waitTimes.add(waitTime);
  }

  @override
  void recordWorkerStarted(int activeCount) {
    workerStartedCount++;
    workerCounts.add(activeCount);
  }

  @override
  void recordWorkerCompleted(int activeCount) {
    workerCompletedCount++;
  }

  @override
  void recordStreamingWorkerHoldTime(Duration holdTime) {
    streamingWorkerHoldTimes.add(holdTime);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  group('SqlExecutionQueue', () {
    test('should execute task immediately when queue is empty and workers available', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
      );

      var executed = false;
      final testResult = await queue.submit<String>(() async {
        executed = true;
        return const res.Success('result');
      });

      expect(executed, isTrue);
      expect(testResult.isSuccess(), isTrue);
      expect(testResult.getOrThrow(), equals('result'));
    });

    test('should expose configured limits', () {
      final queue = SqlExecutionQueue(
        maxQueueSize: 12,
        maxConcurrentWorkers: 3,
        defaultEnqueueTimeout: const Duration(seconds: 7),
      );

      expect(queue.maxQueueSize, 12);
      expect(queue.maxConcurrentWorkers, 3);
      expect(queue.defaultEnqueueTimeout, const Duration(seconds: 7));
    });

    test('should respect FIFO order when processing queued tasks', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
      );

      final executionOrder = <int>[];
      final tasks = <Future<res.Result<int>>>[];

      for (var i = 0; i < 5; i++) {
        final index = i;
        tasks.add(
          queue.submit<int>(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            executionOrder.add(index);
            return res.Success(index);
          }),
        );
      }

      final results = await Future.wait(tasks);
      expect(executionOrder, equals([0, 1, 2, 3, 4]));
      expect(results.every((r) => r.isSuccess()), isTrue);
    });

    test('should let small queries bypass queued batches when batch worker limit is reached', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
        maxConcurrentBatchWorkers: 1,
      );
      final firstBatchBlocker = Completer<void>();
      final executionOrder = <String>[];

      final firstBatch = queue.submit<String>(
        () async {
          executionOrder.add('batch-1-start');
          await firstBatchBlocker.future;
          executionOrder.add('batch-1-end');
          return const res.Success('batch-1');
        },
        kind: SqlExecutionKind.batch,
      );
      await Future<void>.delayed(Duration.zero);

      final secondBatch = queue.submit<String>(
        () async {
          executionOrder.add('batch-2');
          return const res.Success('batch-2');
        },
        kind: SqlExecutionKind.batch,
      );
      final query = queue.submit<String>(
        () async {
          executionOrder.add('query');
          return const res.Success('query');
        },
      );

      await query;
      expect(executionOrder, containsAllInOrder(<String>['batch-1-start', 'query']));
      expect(executionOrder, isNot(contains('batch-2')));

      firstBatchBlocker.complete();
      await Future.wait([firstBatch, secondBatch]);
      expect(executionOrder, containsAllInOrder(<String>['query', 'batch-1-end', 'batch-2']));
      expect(queue.activeBatchWorkers, 0);
    });

    test('should let short queries bypass queued long queries when long query worker limit is reached', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
        maxConcurrentLongQueryWorkers: 1,
      );
      final firstLongBlocker = Completer<void>();
      final executionOrder = <String>[];

      final firstLong = queue.submit<String>(
        () async {
          executionOrder.add('long-1-start');
          await firstLongBlocker.future;
          executionOrder.add('long-1-end');
          return const res.Success('long-1');
        },
        kind: SqlExecutionKind.longQuery,
      );
      await Future<void>.delayed(Duration.zero);

      final secondLong = queue.submit<String>(
        () async {
          executionOrder.add('long-2');
          return const res.Success('long-2');
        },
        kind: SqlExecutionKind.longQuery,
      );
      final shortQuery = queue.submit<String>(
        () async {
          executionOrder.add('short');
          return const res.Success('short');
        },
        kind: SqlExecutionKind.shortQuery,
      );

      await shortQuery;
      expect(executionOrder, containsAllInOrder(<String>['long-1-start', 'short']));
      expect(executionOrder, isNot(contains('long-2')));

      firstLongBlocker.complete();
      await Future.wait([firstLong, secondLong]);
      expect(executionOrder, containsAllInOrder(<String>['short', 'long-1-end', 'long-2']));
      expect(queue.activeLongQueryWorkers, 0);
    });

    test('should let short queries bypass queued non-queries when non-query worker limit is reached', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
        maxConcurrentNonQueryWorkers: 1,
      );
      final firstNonQueryBlocker = Completer<void>();
      final executionOrder = <String>[];

      final firstNonQuery = queue.submit<String>(
        () async {
          executionOrder.add('non-query-1-start');
          await firstNonQueryBlocker.future;
          executionOrder.add('non-query-1-end');
          return const res.Success('non-query-1');
        },
        kind: SqlExecutionKind.nonQuery,
      );
      await Future<void>.delayed(Duration.zero);

      final secondNonQuery = queue.submit<String>(
        () async {
          executionOrder.add('non-query-2');
          return const res.Success('non-query-2');
        },
        kind: SqlExecutionKind.nonQuery,
      );
      final shortQuery = queue.submit<String>(
        () async {
          executionOrder.add('short');
          return const res.Success('short');
        },
        kind: SqlExecutionKind.shortQuery,
      );

      await shortQuery;
      expect(executionOrder, containsAllInOrder(<String>['non-query-1-start', 'short']));
      expect(executionOrder, isNot(contains('non-query-2')));

      firstNonQueryBlocker.complete();
      await Future.wait([firstNonQuery, secondNonQuery]);
      expect(executionOrder, containsAllInOrder(<String>['short', 'non-query-1-end', 'non-query-2']));
      expect(queue.activeNonQueryWorkers, 0);
    });

    test('should reject new requests when queue is full', () async {
      final metrics = _MockMetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 2,
        maxConcurrentWorkers: 1,
        metricsCollector: metrics,
      );

      // Submit tasks to fill the worker and queue
      // Task 1: starts executing immediately (worker=1, queue=0)
      unawaited(
        queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return const res.Success(1);
        }),
      );
      // Task 2: goes to queue (worker=1, queue=1)
      unawaited(
        queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return const res.Success(1);
        }),
      );
      // Task 3: goes to queue (worker=1, queue=2)
      unawaited(
        queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return const res.Success(1);
        }),
      );

      // Wait a bit to ensure queue is filled
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Task 4: should be rejected (queue is full)
      final result = await queue.submit<int>(() async {
        return const res.Success(1);
      });

      expect(result.isError(), isTrue);
      final Object? exc = result.exceptionOrNull();
      expect(exc, isA<ConfigurationFailure>());
      if (exc is! ConfigurationFailure) {
        fail('expected ConfigurationFailure');
      }
      expect(exc.message, contains('SQL execution queue is full'));
      expect(exc.context['reason'], equals('sql_queue_full'));
      expect(exc.context['rpc_error_code'], equals(RpcErrorCode.rateLimited));
      expect(exc.context['retryable'], isTrue);
      expect(exc.isTransient, isTrue);
      expect((exc.context['user_message'] as String?)?.isNotEmpty, isTrue);
      expect(metrics.queueRejectionCount, equals(1));
    });

    test('should reject overflow after workers and queue are deterministically filled', () async {
      final metrics = _MockMetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 2,
        maxConcurrentWorkers: 1,
        metricsCollector: metrics,
      );
      final blocker = Completer<void>();

      final acceptedFutures = <Future<res.Result<int>>>[];
      for (var index = 0; index < 3; index++) {
        acceptedFutures.add(
          queue.submit<int>(() async {
            await blocker.future;
            return res.Success(index);
          }),
        );
      }

      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (DateTime.now().isBefore(deadline) && queue.queueSize < queue.maxQueueSize) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(queue.activeWorkers, 1);
      expect(queue.queueSize, queue.maxQueueSize);

      final overflow = await queue.submit<int>(() async => const res.Success(99));

      expect(overflow.isError(), isTrue);
      final error = overflow.exceptionOrNull();
      expect(error, isA<ConfigurationFailure>());
      expect((error! as ConfigurationFailure).context['reason'], 'sql_queue_full');
      expect(metrics.queueRejectionCount, 1);

      blocker.complete();
      final accepted = await Future.wait(acceptedFutures);
      expect(accepted.where((result) => result.isSuccess()).length, 3);
    });

    test('should record queue saturation threshold crossings', () async {
      final metrics = _MockMetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
        metricsCollector: metrics,
      );
      final blocker = Completer<void>();
      final futures = <Future<res.Result<String>>>[];

      futures.add(
        queue.submit<String>(() async {
          await blocker.future;
          return const res.Success('active');
        }),
      );
      await Future<void>.delayed(Duration.zero);

      for (var index = 0; index < 9; index++) {
        futures.add(
          queue.submit<String>(() async => const res.Success('queued')),
        );
      }
      await Future<void>.delayed(Duration.zero);

      expect(metrics.saturationThresholds, containsAllInOrder(<int>[70, 90]));

      blocker.complete();
      await Future.wait(futures);
    });

    test('should enforce concurrent worker limit', () async {
      final metrics = _MockMetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
        metricsCollector: metrics,
      );

      var maxConcurrent = 0;
      var currentConcurrent = 0;

      final tasks = <Future<res.Result<int>>>[];
      for (var i = 0; i < 5; i++) {
        tasks.add(
          queue.submit<int>(() async {
            currentConcurrent++;
            if (currentConcurrent > maxConcurrent) {
              maxConcurrent = currentConcurrent;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
            currentConcurrent--;
            return const res.Success(1);
          }),
        );
      }

      await Future.wait(tasks);
      expect(maxConcurrent, lessThanOrEqualTo(2));
    });

    test('should timeout requests that wait too long in queue', () async {
      final metrics = _MockMetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
        metricsCollector: metrics,
      );

      // Start a slow task
      unawaited(
        queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return const res.Success(1);
        }),
      );

      // This should timeout waiting in queue
      final result = await queue.submit<int>(
        () async {
          return const res.Success(1);
        },
        enqueueTimeout: const Duration(milliseconds: 50),
      );

      expect(result.isError(), isTrue);
      final Object? excTimeout = result.exceptionOrNull();
      expect(excTimeout, isA<QueryExecutionFailure>());
      if (excTimeout is! QueryExecutionFailure) {
        fail('expected QueryExecutionFailure');
      }
      expect(excTimeout.message, contains('timed out waiting in queue'));
      expect(excTimeout.context['reason'], equals('queue_wait_timeout'));
      expect(excTimeout.context['rpc_error_code'], equals(RpcErrorCode.rateLimited));
      expect(excTimeout.context['timeout'], isTrue);
      expect(excTimeout.context['timeout_stage'], equals('queue'));
      expect(excTimeout.context['retryable'], isTrue);
      expect((excTimeout.context['user_message'] as String?)?.isNotEmpty, isTrue);
      expect(metrics.queueTimeoutCount, equals(1));
    });

    test('should cancel cooperative token when queue wait times out before worker starts', () async {
      final metrics = _MockMetricsCollector();
      final cooperativeToken = CancellationToken();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
        metricsCollector: metrics,
      );
      final blocker = Completer<void>();

      unawaited(
        queue.submit<int>(() async {
          await blocker.future;
          return const res.Success(1);
        }),
      );
      await Future<void>.delayed(Duration.zero);

      final result = await queue.submit<int>(
        () async => const res.Success(2),
        enqueueTimeout: const Duration(milliseconds: 20),
        cooperativeCancellationToken: cooperativeToken,
      );

      expect(result.isError(), isTrue);
      expect(cooperativeToken.isCancelled, isTrue);
      expect(metrics.queueTimeoutAfterWorkerStartedCount, 0);

      blocker.complete();
    });

    test('should request native abort port when queue wait times out after worker started', () async {
      final abortPort = _MockInFlightAbortPort();
      when(() => abortPort.abortInFlightExecution(any())).thenAnswer((_) async => const res.Success(res.unit));
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
        inFlightAbortPort: abortPort,
      );

      final failure = queue.recordQueueWaitTimeoutForTesting(
        workerStarted: true,
        requestId: 'ghost-race',
      );

      expect(failure.context['ghost_query_risk'], isTrue);
      await Future<void>.delayed(Duration.zero);
      verify(() => abortPort.abortInFlightExecution('ghost-race')).called(1);
    });

    test('should record after-worker-started timeout metric and cooperative cancel', () {
      final metrics = _MockMetricsCollector();
      final cooperativeToken = CancellationToken();
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
        metricsCollector: metrics,
      );

      final failure = queue.recordQueueWaitTimeoutForTesting(
        workerStarted: true,
        cooperativeCancellationToken: cooperativeToken,
        requestId: 'ghost-race',
      );

      expect(failure.context['ghost_query_risk'], isTrue);
      expect(failure.context['worker_started'], isTrue);
      expect(cooperativeToken.isCancelled, isTrue);
      expect(metrics.queueTimeoutCount, 1);
      expect(metrics.queueTimeoutAfterWorkerStartedCount, 1);
    });

    test('mock ODBC worker may continue when queue layer only signals cooperative cancel', () async {
      final cooperativeToken = CancellationToken();
      var mockOdbcCompleted = false;

      unawaited(
        Future<void>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          mockOdbcCompleted = true;
        }),
      );
      cooperativeToken.cancel();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mockOdbcCompleted, isTrue);
      expect(cooperativeToken.isCancelled, isTrue);
    });

    test('should apply enqueue timeout only before task starts', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
      );

      final result = await queue.submit<int>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return const res.Success(7);
        },
        enqueueTimeout: const Duration(milliseconds: 10),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), equals(7));
    });

    test('should not execute a request cancelled after dequeue race', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
      );
      final firstStarted = Completer<void>();

      unawaited(
        queue.submit<int>(() async {
          await firstStarted.future;
          return const res.Success(1);
        }),
      );
      await Future<void>.delayed(Duration.zero);

      var executedCancelledTask = false;
      final cancelled = queue.submit<int>(
        () async {
          executedCancelledTask = true;
          return const res.Success(2);
        },
        enqueueTimeout: const Duration(milliseconds: 20),
      );

      final result = await cancelled;
      expect(result.isError(), isTrue);

      firstStarted.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(executedCancelledTask, isFalse);
    });

    test('should not execute a request that timed out before start', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
      );

      unawaited(
        queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return const res.Success(1);
        }),
      );

      var executedTimedOutTask = false;
      final result = await queue.submit<int>(
        () async {
          executedTimedOutTask = true;
          return const res.Success(2);
        },
        enqueueTimeout: const Duration(milliseconds: 20),
      );

      expect(result.isError(), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(executedTimedOutTask, isFalse);
    });

    test('should record queue metrics correctly', () async {
      final metrics = _MockMetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
        metricsCollector: metrics,
      );

      await queue.submit<int>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return const res.Success(1);
      });

      expect(metrics.queueAddedCount, equals(1));
      expect(metrics.workerStartedCount, equals(1));
      expect(metrics.workerCompletedCount, equals(1));
      expect(metrics.waitTimes, hasLength(1));
    });

    test('should update current queue size metrics when requests are dequeued', () async {
      final metrics = _MockMetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
        metricsCollector: metrics,
      );

      await queue.submit<int>(() async {
        return const res.Success(1);
      });

      expect(metrics.queueSizes, contains(1));
      expect(metrics.queueSizes.last, equals(0));
    });

    test('should handle task failures gracefully', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
      );

      final result = await queue.submit<String>(() async {
        return res.Failure(QueryExecutionFailure('Task failed'));
      });

      expect(result.isError(), isTrue);
      final Object? excTask = result.exceptionOrNull();
      expect(excTask, isA<QueryExecutionFailure>());
      if (excTask is! QueryExecutionFailure) {
        fail('expected QueryExecutionFailure');
      }
      expect(excTask.message, equals('Task failed'));
    });

    test('should handle task exceptions', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
      );

      final result = await queue.submit<String>(() async {
        throw Exception('Unexpected error');
      });

      expect(result.isError(), isTrue);
      final Object? error = result.exceptionOrNull();
      expect(error, isA<ServerFailure>());
      if (error is! ServerFailure) {
        fail('expected ServerFailure');
      }
      expect(error.message, contains('unexpected error'));
      expect(error.context['reason'], equals(SqlPipelineContextConstants.unexpectedTaskErrorReason));
    });

    test('should report queue size and active workers correctly', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
      );

      expect(queue.queueSize, equals(0));
      expect(queue.activeWorkers, equals(0));

      final task1Future = queue.submit<int>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const res.Success(1);
      });

      final task2Future = queue.submit<int>(() async {
        return const res.Success(1);
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(queue.activeWorkers, equals(1));
      expect(queue.queueSize, greaterThanOrEqualTo(0));

      await Future.wait([task1Future, task2Future]);
      expect(queue.queueSize, equals(0));
      expect(queue.activeWorkers, equals(0));
    });

    test('should reject requests after disposal', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
      );

      queue.dispose();

      final result = await queue.submit<int>(() async {
        return const res.Success(1);
      });

      expect(result.isError(), isTrue);
      final Object? excDisposed = result.exceptionOrNull();
      expect(excDisposed, isA<ConfigurationFailure>());
      if (excDisposed is! ConfigurationFailure) {
        fail('expected ConfigurationFailure');
      }
      expect(excDisposed.message, contains('disposed'));
      expect(excDisposed.context['reason'], equals(SqlPipelineContextConstants.queueDisposedReason));
    });

    test('should complete pending requests with error on disposal', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
      );

      // Start a slow task
      unawaited(
        queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return const res.Success(1);
        }),
      );

      // Queue another task
      final pendingTask = queue.submit<int>(() async {
        return const res.Success(1);
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));

      queue.dispose();

      final result = await pendingTask;

      expect(result.isError(), isTrue);
      final Object? error = result.exceptionOrNull();
      expect(error, isA<ConfigurationFailure>());
      if (error is! ConfigurationFailure) {
        fail('expected ConfigurationFailure');
      }
      expect(error.message, contains('disposed before request could be processed'));
      expect(error.context['reason'], equals(SqlPipelineContextConstants.queueDisposedReason));
      expect((error.context['user_message'] as String?)?.isNotEmpty, isTrue);
    });

    test('should process multiple tasks concurrently up to worker limit', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 20,
        maxConcurrentWorkers: 4,
      );

      var peakConcurrent = 0;
      var currentConcurrent = 0;
      final tasks = <Future<res.Result<int>>>[];

      for (var i = 0; i < 8; i++) {
        tasks.add(
          queue.submit<int>(() async {
            currentConcurrent++;
            if (currentConcurrent > peakConcurrent) {
              peakConcurrent = currentConcurrent;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
            currentConcurrent--;
            return const res.Success(1);
          }),
        );
      }

      await Future.wait(tasks);

      expect(peakConcurrent, equals(4));
    });

    test('should handle requestId in context', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 1,
        maxConcurrentWorkers: 1,
      );

      // Submit tasks to fill worker and queue
      // Task 1: starts executing (worker=1, queue=0)
      unawaited(
        queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return const res.Success(1);
        }),
      );
      // Task 2: goes to queue (worker=1, queue=1)
      unawaited(
        queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return const res.Success(1);
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Task 3: should be rejected with requestId in context
      final result = await queue.submit<int>(
        () async {
          return const res.Success(1);
        },
        requestId: 'test-request-123',
      );

      expect(result.isError(), isTrue);
      final Object? excReq = result.exceptionOrNull();
      expect(excReq, isA<ConfigurationFailure>());
      if (excReq is! ConfigurationFailure) {
        fail('expected ConfigurationFailure');
      }
      expect(excReq.context['request_id'], equals('test-request-123'));
    });

    group('full rejection throttling', () {
      test('should count consecutive full rejections', () async {
        final queue = SqlExecutionQueue(
          maxQueueSize: 1,
          maxConcurrentWorkers: 1,
        );

        // First submission keeps the only worker busy long enough that the
        // queue saturates and subsequent submissions are rejected.
        unawaited(
          queue.submit<int>(() async {
            await Future<void>.delayed(const Duration(milliseconds: 80));
            return const res.Success(1);
          }),
        );
        // Second submission goes into the queue (queue=1, isFull=true).
        unawaited(
          queue.submit<int>(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return const res.Success(1);
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(queue.consecutiveFullRejections, 0);

        for (var i = 0; i < 3; i++) {
          final rejected = await queue.submit<int>(
            () async => const res.Success(99),
          );
          expect(rejected.isError(), isTrue);
        }

        expect(queue.consecutiveFullRejections, 3);
      });

      test('should reset rejection counter when a submission is accepted', () async {
        final queue = SqlExecutionQueue(
          maxQueueSize: 1,
          maxConcurrentWorkers: 1,
        );

        final firstFuture = queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return const res.Success(1);
        });
        final queuedFuture = queue.submit<int>(() async {
          return const res.Success(2);
        });
        await Future<void>.delayed(const Duration(milliseconds: 5));

        for (var i = 0; i < 2; i++) {
          await queue.submit<int>(() async => const res.Success(99));
        }
        expect(queue.consecutiveFullRejections, 2);

        await firstFuture;
        await queuedFuture;

        // Queue drained; the next submission is accepted and the counter
        // resets so a later saturation burst starts a fresh logging episode.
        final accepted = await queue.submit<int>(() async => const res.Success(3));
        expect(accepted.isSuccess(), isTrue);
        expect(queue.consecutiveFullRejections, 0);
      });

      test('should reject custom log stride that is not positive', () {
        expect(
          () => SqlExecutionQueue(
            maxQueueSize: 1,
            maxConcurrentWorkers: 1,
            fullRejectionLogStride: 0,
          ),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('disposeGracefully', () {
      test('should complete immediately when queue is idle', () async {
        final queue = SqlExecutionQueue(
          maxQueueSize: 4,
          maxConcurrentWorkers: 2,
        );

        final result = await queue.disposeGracefully();

        expect(result.isSuccess(), isTrue);
      });

      test('should wait for in-flight workers before completing', () async {
        final queue = SqlExecutionQueue(
          maxQueueSize: 4,
          maxConcurrentWorkers: 2,
        );

        var taskFinished = false;
        final inFlight = queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          taskFinished = true;
          return const res.Success(1);
        });
        // Give the worker a tick to start before disposing.
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final disposeResult = await queue.disposeGracefully();
        await inFlight;

        expect(disposeResult.isSuccess(), isTrue);
        expect(taskFinished, isTrue);
        expect(queue.activeWorkers, equals(0));
      });

      test('should fail pending requests but still drain in-flight workers', () async {
        final queue = SqlExecutionQueue(
          maxQueueSize: 4,
          maxConcurrentWorkers: 1,
        );

        final inFlight = queue.submit<int>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          return const res.Success(1);
        });
        final queued = queue.submit<int>(() async {
          return const res.Success(2);
        });
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final disposeResult = await queue.disposeGracefully();
        final inFlightResult = await inFlight;
        final queuedResult = await queued;

        expect(disposeResult.isSuccess(), isTrue);
        expect(inFlightResult.isSuccess(), isTrue);
        expect(queuedResult.isError(), isTrue);
        final queuedError = queuedResult.exceptionOrNull();
        expect(queuedError, isA<ConfigurationFailure>());
      });

      test('should return failure when in-flight workers exceed timeout', () async {
        final queue = SqlExecutionQueue(
          maxQueueSize: 4,
          maxConcurrentWorkers: 1,
        );

        unawaited(
          queue.submit<int>(() async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return const res.Success(1);
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final disposeResult = await queue.disposeGracefully(
          timeout: const Duration(milliseconds: 30),
        );

        expect(disposeResult.isError(), isTrue);
        final failure = disposeResult.exceptionOrNull();
        expect(failure, isA<QueryExecutionFailure>());
        if (failure is! QueryExecutionFailure) {
          fail('expected QueryExecutionFailure');
        }
        expect(failure.context['timeout'], isTrue);
        expect(failure.context['timeout_stage'], equals('shutdown'));
      });
    });

    test('should let short queries bypass queued streams when streaming worker limit is reached', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
        maxConcurrentStreamingWorkers: 1,
      );
      final firstStreamBlocker = Completer<void>();
      final executionOrder = <String>[];

      final firstStream = queue.submit<String>(
        () async {
          executionOrder.add('stream-1-start');
          await firstStreamBlocker.future;
          executionOrder.add('stream-1-end');
          return const res.Success('stream-1');
        },
        kind: SqlExecutionKind.streaming,
      );
      await Future<void>.delayed(Duration.zero);

      final secondStream = queue.submit<String>(
        () async {
          executionOrder.add('stream-2');
          return const res.Success('stream-2');
        },
        kind: SqlExecutionKind.streaming,
      );
      final shortQuery = queue.submit<String>(
        () async {
          executionOrder.add('short');
          return const res.Success('short');
        },
        kind: SqlExecutionKind.shortQuery,
      );

      await shortQuery;
      expect(executionOrder, containsAllInOrder(<String>['stream-1-start', 'short']));
      expect(executionOrder, isNot(contains('stream-2')));

      firstStreamBlocker.complete();
      await Future.wait([firstStream, secondStream]);
      expect(executionOrder, containsAllInOrder(<String>['short', 'stream-1-end', 'stream-2']));
      expect(queue.activeStreamingWorkers, 0);
    });

    test('should record streaming worker hold time while stream task runs', () async {
      final metrics = _MockMetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
        metricsCollector: metrics,
      );

      await queue.submit<String>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return const res.Success('stream');
        },
        kind: SqlExecutionKind.streaming,
      );

      expect(metrics.streamingWorkerHoldTimes, hasLength(1));
      expect(metrics.streamingWorkerHoldTimes.first.inMilliseconds, greaterThanOrEqualTo(35));
    });

    test('should cancel cooperative token on releasable streaming queue wait timeout', () async {
      final cooperativeToken = CancellationToken();
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
      );
      final blocker = Completer<void>();

      unawaited(
        queue.submit<int>(() async {
          await blocker.future;
          return const res.Success(1);
        }),
      );
      await Future<void>.delayed(Duration.zero);

      final result = await queue.submitWithReleasableWorker<int>(
        (releaseWorker) async {
          releaseWorker();
          await Future<void>.delayed(const Duration(seconds: 1));
          return const res.Success(2);
        },
        enqueueTimeout: const Duration(milliseconds: 20),
        kind: SqlExecutionKind.streaming,
        cooperativeCancellationToken: cooperativeToken,
      );

      expect(result.isError(), isTrue);
      expect(cooperativeToken.isCancelled, isTrue);

      blocker.complete();
    });

    test('should release worker before releasable streaming task completes', () async {
      final metrics = _MockMetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
        metricsCollector: metrics,
      );
      final streamBlocker = Completer<void>();
      var secondTaskStarted = false;

      final streamFuture = queue.submitWithReleasableWorker<String>(
        (releaseWorker) async {
          releaseWorker();
          await streamBlocker.future;
          return const res.Success('stream');
        },
        kind: SqlExecutionKind.streaming,
      );
      await Future<void>.delayed(Duration.zero);

      expect(queue.activeWorkers, 0);
      expect(queue.activeStreamingWorkers, 0);
      expect(metrics.streamingWorkerHoldTimes, hasLength(1));

      final secondFuture = queue.submit<String>(
        () async {
          secondTaskStarted = true;
          return const res.Success('query');
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(secondTaskStarted, isTrue);

      streamBlocker.complete();
      final streamResult = await streamFuture;
      final secondResult = await secondFuture;

      expect(streamResult.isSuccess(), isTrue);
      expect(secondResult.isSuccess(), isTrue);
      expect(queue.activeWorkers, 0);
    });

    test('should execute streaming tasks through the shared worker pool', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
      );
      final blocker = Completer<void>();
      var streamingStarted = false;

      unawaited(
        queue.submit<String>(
          () async {
            streamingStarted = true;
            await blocker.future;
            return const res.Success('stream-1');
          },
          kind: SqlExecutionKind.streaming,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(streamingStarted, isTrue);
      expect(queue.activeWorkers, 1);

      final queued = queue.submit<String>(
        () async => const res.Success('stream-2'),
        kind: SqlExecutionKind.streaming,
      );
      await Future<void>.delayed(Duration.zero);
      expect(queue.activeWorkers, 1);

      blocker.complete();
      await queued;
      expect(queue.activeWorkers, 0);
    });
  });
}
