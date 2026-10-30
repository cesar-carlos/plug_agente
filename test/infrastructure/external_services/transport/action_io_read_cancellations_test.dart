import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/infrastructure/external_services/transport/action_io_read_cancellations.dart';

void main() {
  var elapsed = Duration.zero;
  late ActionIoReadCancellations registry;
  setUp(() {
    elapsed = Duration.zero;
    registry = ActionIoReadCancellations(elapsed: () => elapsed);
  });

  test('control before decoding cancels only the matching generation and typed ID', () {
    registry.cancel(generation: 1, requestId: 7).getOrThrow();
    expect(registry.acquire(generation: 2, requestId: 7).getOrThrow().isCancelled, isFalse);
    expect(registry.acquire(generation: 1, requestId: '7').getOrThrow().isCancelled, isFalse);
    expect(registry.acquire(generation: 1, requestId: 7).getOrThrow().isCancelled, isTrue);
  });

  test('active cancellation remains visible until release, even after retention', () {
    final lease = registry.acquire(generation: 1, requestId: 'read').getOrThrow();
    elapsed = const Duration(minutes: 1);
    registry.cancel(generation: 1, requestId: 'read').getOrThrow();
    expect(lease.isCancelled, isTrue);
    expect(registry.acquire(generation: 1, requestId: 'read').isError(), isTrue);
    lease.release();
    lease.release();
    expect(registry.acquire(generation: 1, requestId: 'read').getOrThrow().isCancelled, isFalse);
  });

  test('early controls expire and duplicates do not extend their lifetime', () {
    registry.cancel(generation: 1, requestId: 'read').getOrThrow();
    elapsed = const Duration(seconds: 29);
    registry.cancel(generation: 1, requestId: 'read').getOrThrow();
    elapsed = const Duration(seconds: 30);
    expect(registry.acquire(generation: 1, requestId: 'read').getOrThrow().isCancelled, isFalse);
  });

  test('combined capacity is bounded without evicting active or early cancellation', () {
    final lease = registry.acquire(generation: 1, requestId: 'active').getOrThrow();
    for (var id = 0; id < ActionIoReadCancellations.capacity - 1; id++) {
      registry.cancel(generation: 1, requestId: id).getOrThrow();
    }
    final refused = registry.cancel(generation: 1, requestId: 'overflow');
    expect(refused.exceptionOrNull(), isA<ActionRuntimeFailure>());
    expect((refused.exceptionOrNull()! as ActionRuntimeFailure).code, 'ACTION_IO_READER_LIMIT');
    expect(registry.acquire(generation: 1, requestId: 'overflow').isError(), isTrue);
    expect(registry.acquire(generation: 1, requestId: 0).getOrThrow().isCancelled, isTrue);
    registry.cancel(generation: 1, requestId: 'active').getOrThrow();
    expect(lease.isCancelled, isTrue);
    elapsed = const Duration(seconds: 31);
    expect(registry.acquire(generation: 1, requestId: 'overflow').isSuccess(), isTrue);
  });

  test('reset cancels held leases and stale release cannot remove a new lease', () {
    final old = registry.acquire(generation: 1, requestId: 'read').getOrThrow();
    registry.reset();
    expect(old.isCancelled, isTrue);
    final current = registry.acquire(generation: 1, requestId: 'read').getOrThrow();
    old.release();
    registry.cancel(generation: 1, requestId: 'read').getOrThrow();
    expect(current.isCancelled, isTrue);
  });
}
