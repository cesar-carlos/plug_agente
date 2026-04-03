import 'dart:async';
import 'dart:collection';

/// Simple FIFO semaphore for limiting concurrent leases.
class PoolSemaphore {
  PoolSemaphore(int maxConcurrent)
    : assert(maxConcurrent > 0, 'maxConcurrent must be greater than zero'),
      _maxConcurrent = maxConcurrent,
      _available = maxConcurrent;

  final int _maxConcurrent;
  int _available;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Future<void> acquire({Duration? timeout}) async {
    if (_available > 0) {
      _available--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.addLast(completer);

    if (timeout == null) {
      await completer.future;
      return;
    }

    try {
      await completer.future.timeout(timeout);
    } on TimeoutException catch (_) {
      final removed = _waitQueue.remove(completer);
      if (removed) {
        throw TimeoutException('Pool acquire timed out after ${timeout.inMilliseconds}ms');
      }
      // When not removed, release has already handed the permit to this waiter.
      await completer.future;
    }
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final waiter = _waitQueue.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete();
      }
      return;
    }

    if (_available < _maxConcurrent) {
      _available++;
    }
  }
}
