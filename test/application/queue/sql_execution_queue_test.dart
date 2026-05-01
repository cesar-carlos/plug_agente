import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:result_dart/result_dart.dart' as res;

class _MockMetricsCollector implements SqlExecutionQueueMetricsCollector {
  int queueAddedCount = 0;
  int queueRejectionCount = 0;
  int queueTimeoutCount = 0;
  int workerStartedCount = 0;
  int workerCompletedCount = 0;
  final List<Duration> waitTimes = [];
  final List<int> queueSizes = [];
  final List<int> workerCounts = [];

  @override
  void recordQueueAdded(int currentSize) {
    queueAddedCount++;
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
}

void main() {
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
      expect(metrics.queueRejectionCount, equals(1));
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
      expect(metrics.queueTimeoutCount, equals(1));
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

      try {
        await queue.submit<String>(() async {
          throw Exception('Unexpected error');
        });
        fail('Should have thrown an exception');
      } on Object catch (error) {
        expect(error, isA<QueryExecutionFailure>());
        if (error is! QueryExecutionFailure) {
          fail('expected QueryExecutionFailure');
        }
        expect(error.message, contains('unexpected error'));
      }
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
      expect(excDisposed.context['reason'], equals('queue_disposed'));
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

      try {
        await pendingTask;
        fail('Should have thrown an exception');
      } on Object catch (error) {
        expect(error, isA<ConfigurationFailure>());
        if (error is! ConfigurationFailure) {
          fail('expected ConfigurationFailure');
        }
        expect(error.message, contains('disposed before request could be processed'));
      }
    });

    test('should process multiple tasks concurrently up to worker limit', () async {
      final queue = SqlExecutionQueue(
        maxQueueSize: 20,
        maxConcurrentWorkers: 4,
      );

      final startTime = DateTime.now();
      final tasks = <Future<res.Result<int>>>[];

      // Submit 8 tasks that each take 50ms
      for (var i = 0; i < 8; i++) {
        tasks.add(
          queue.submit<int>(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return const res.Success(1);
          }),
        );
      }

      await Future.wait(tasks);
      final elapsed = DateTime.now().difference(startTime);

      // With 4 workers, 8 tasks should complete in ~100ms (2 batches)
      // Allow some overhead for scheduling
      expect(elapsed.inMilliseconds, lessThan(200));
      expect(elapsed.inMilliseconds, greaterThan(80));
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
  });
}
