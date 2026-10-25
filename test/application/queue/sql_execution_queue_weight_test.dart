import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  test('an oversized batch cannot block a valid batch in the same lane', () async {
    final queue = SqlExecutionQueue(maxQueueSize: 4, maxConcurrentWorkers: 2, maxConcurrentBatchWorkers: 2);
    addTearDown(queue.dispose);
    final oversized = queue.submit(
      () async => const Success(0),
      kind: SqlExecutionKind.batch,
      slotWeight: 3,
      enqueueTimeout: const Duration(milliseconds: 20),
    );
    var invoked = 0;
    final valid = queue.submit(
      () async {
        invoked++;
        return const Success(1);
      },
      kind: SqlExecutionKind.batch,
      slotWeight: 2,
      enqueueTimeout: const Duration(milliseconds: 100),
    );
    expect((await oversized).exceptionOrNull(), isA<ValidationFailure>());
    expect((await valid).getOrNull(), 1);
    expect(invoked, 1);
    expect(queue.activeWorkers, 0);
  });

  for (final releasable in [false, true]) {
    for (final weight in [-1, 0, 3]) {
      test('rejects invalid batch weight $weight (releasable: $releasable)', () async {
        final queue = SqlExecutionQueue(maxQueueSize: 4, maxConcurrentWorkers: 2, maxConcurrentBatchWorkers: 2);
        addTearDown(queue.dispose);
        var invoked = 0;
        Future<Result<int>> task() async {
          invoked++;
          return const Success(1);
        }

        final result = releasable
            ? await queue.submitWithReleasableWorker(
                (_) => task(),
                kind: SqlExecutionKind.batch,
                slotWeight: weight,
                enqueueTimeout: const Duration(milliseconds: 20),
              )
            : await queue.submit(
                task,
                kind: SqlExecutionKind.batch,
                slotWeight: weight,
                enqueueTimeout: const Duration(milliseconds: 20),
              );
        expect(result.exceptionOrNull(), isA<ValidationFailure>());
        expect(invoked, 0);
        expect(queue.queueSize, 0);
        expect(queue.activeWorkers, 0);
        expect(queue.activeBatchWorkers, 0);
        expect((await queue.submit(task)).isSuccess(), isTrue);
        expect(invoked, 1);
      });
    }
  }
}
