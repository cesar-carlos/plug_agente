import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _ObservedToken extends CancellationToken {
  int listeners = 0;
  late final events = StreamController<void>.broadcast(
    onListen: () => listeners++,
    onCancel: () => listeners--,
  );
  @override
  Stream<void> get cancellations => events.stream;
}

class _Metrics extends Mock implements SqlExecutionQueueMetricsCollector {}

void main() {
  test('500 cancellations drain waiters without timeout metrics or premature worker release', () async {
    final metrics = _Metrics();
    final queue = SqlExecutionQueue(maxQueueSize: 500, maxConcurrentWorkers: 1, metricsCollector: metrics);
    final release = Completer<Result<int>>();
    final active = queue.submit(() => release.future);
    final tokens = List.generate(500, (_) => CancellationToken());
    var dispatched = 0;
    final pending = [
      for (final token in tokens)
        queue.submit(() async {
          dispatched++;
          return const Success(2);
        }, cooperativeCancellationToken: token),
    ];
    try {
      expect(queue.queueSize, 500);
      for (final token in tokens.reversed) {
        token.cancel();
      }
      final results = await Future.wait(pending);
      expect(results.every((r) => r.isError()), isTrue);
      expect(dispatched, 0);
      expect(queue.queueSize, 0);
      expect(queue.activeWorkers, 1);
      verifyNever(metrics.recordQueueTimeout);
      verifyNever(metrics.recordQueueTimeoutAfterWorkerStarted);
      verifyNever(() => metrics.recordWorkerCompleted(any()));
      final draining = queue.disposeGracefully();
      expect((await queue.submit(() async => const Success(3))).isError(), isTrue);
      release.complete(const Success(1));
      await active;
      expect((await draining).isSuccess(), isTrue);
      expect(queue.activeWorkers, 0);
      verify(() => metrics.recordWorkerCompleted(0)).called(1);
    } finally {
      if (!release.isCompleted) release.complete(const Success(1));
      await active;
      queue.dispose();
    }
  });

  for (final outcome in ['completion', 'timeout', 'disposal']) {
    test('detaches the cancellation subscription after $outcome', () async {
      final queue = SqlExecutionQueue(maxQueueSize: 4, maxConcurrentWorkers: 1);
      final token = _ObservedToken();
      final release = Completer<Result<int>>();
      final blocker = outcome == 'completion' ? null : queue.submit(() => release.future);
      try {
        final result = queue.submit(
          () async => const Success(1),
          cooperativeCancellationToken: token,
          enqueueTimeout: const Duration(milliseconds: 20),
        );
        if (outcome == 'disposal') queue.dispose();
        expect((await result).isSuccess(), outcome == 'completion');
        expect(token.listeners, 0);
      } finally {
        release.complete(const Success(1));
        await blocker;
        queue.dispose();
        await token.events.close();
      }
    });
  }

  test('disposal wins over a pending cancellation event without corrupting counts', () async {
    final queue = SqlExecutionQueue(maxQueueSize: 4, maxConcurrentWorkers: 1);
    final release = Completer<Result<int>>();
    final blocker = queue.submit(() => release.future);
    final token = CancellationToken();
    final pending = queue.submit(() async => fail('Cancelled task dispatched'), cooperativeCancellationToken: token);
    token.cancel();
    queue.dispose();
    expect((await pending).isError(), isTrue);
    expect(queue.queueSize, 0);
    expect(queue.activeWorkers, 1);
    release.complete(const Success(1));
    await blocker;
    expect(queue.activeWorkers, 0);
  });

  for (final releasable in [false, true]) {
    test('queued cancellation frees admission while the worker is busy (releasable: $releasable)', () async {
      final queue = SqlExecutionQueue(maxQueueSize: 1, maxConcurrentWorkers: 1);
      final release = Completer<Result<int>>();
      final blocker = queue.submit(() => release.future);
      final token = CancellationToken();
      var calls = 0;
      Future<Result<int>> task() async {
        calls++;
        return const Success(2);
      }

      final cancelled = releasable
          ? queue.submitWithReleasableWorker((_) => task(), cooperativeCancellationToken: token)
          : queue.submit(task, cooperativeCancellationToken: token);
      try {
        expect(queue.queueSize, 1);
        token.cancel();
        await Future<void>.delayed(Duration.zero);
        expect(queue.queueSize, 0);
        expect(queue.activeWorkers, 1);
        expect((await cancelled).isError(), isTrue);
        final admitted = queue.submit(task);
        expect(queue.queueSize, 1);
        release.complete(const Success(1));
        await blocker;
        expect((await admitted).getOrNull(), 2);
        expect(calls, 1);
      } finally {
        if (!release.isCompleted) release.complete(const Success(1));
        await blocker;
        queue.dispose();
        await cancelled;
      }
    });

    test('cancellation after start retains the worker until completion (releasable: $releasable)', () async {
      final queue = SqlExecutionQueue(maxQueueSize: 4, maxConcurrentWorkers: 1);
      addTearDown(queue.dispose);
      final token = CancellationToken();
      final started = Completer<void>();
      final completion = Completer<Result<int>>();
      Future<Result<int>> task() {
        started.complete();
        return completion.future;
      }

      final running = releasable
          ? queue.submitWithReleasableWorker((_) => task(), cooperativeCancellationToken: token)
          : queue.submit(task, cooperativeCancellationToken: token);
      await started.future;
      token.cancel();
      var nextCalls = 0;
      final next = queue.submit(() async {
        nextCalls++;
        return const Success(2);
      });
      expect(queue.activeWorkers, 1);
      expect(nextCalls, 0);
      completion.complete(const Success(1));
      expect((await running).getOrNull(), 1);
      expect((await next).getOrNull(), 2);
      expect(nextCalls, 1);
      expect(queue.activeWorkers, 0);
    });

    for (final waiting in [false, true]) {
      test('cancel before dispatch skips task (releasable: $releasable, queued: $waiting)', () async {
        final queue = SqlExecutionQueue(maxQueueSize: 4, maxConcurrentWorkers: 1);
        addTearDown(queue.dispose);
        final release = Completer<Result<int>>();
        final blocker = waiting ? queue.submit(() => release.future) : null;
        final token = CancellationToken();
        if (!waiting) token.cancel();
        var calls = 0;
        Future<Result<int>> task() async {
          calls++;
          return const Success(1);
        }

        final pending = releasable
            ? queue.submitWithReleasableWorker((_) => task(), cooperativeCancellationToken: token)
            : queue.submit(task, cooperativeCancellationToken: token);
        token.cancel();
        if (waiting) {
          release.complete(const Success(1));
          await blocker;
        }
        final result = await pending;
        expect(calls, 0);
        final failure = result.exceptionOrNull();
        expect(failure, isA<domain.QueryExecutionFailure>());
        expect((failure! as domain.Failure).context['execution_not_started'], isTrue);
        expect((failure as domain.Failure).context['reason'], 'execution_cancelled');
        expect(queue.activeWorkers, 0);
        expect(queue.queueSize, 0);
        expect((await queue.submit(task)).isSuccess(), isTrue);
        expect(calls, 1);
      });
    }
  }
}
