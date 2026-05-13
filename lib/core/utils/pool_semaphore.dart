import 'dart:async';
import 'dart:collection';

/// Simple FIFO semaphore for limiting concurrent leases.
class PoolSemaphore {
  PoolSemaphore(int maxConcurrent)
    : assert(maxConcurrent > 0, 'maxConcurrent must be greater than zero'),
      _maxConcurrent = maxConcurrent;

  int _maxConcurrent;
  int _activeCount = 0;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  int get maxConcurrent => _maxConcurrent;

  int get activeCount => _activeCount;

  Future<void> acquire({Duration? timeout}) async {
    if (_activeCount < _maxConcurrent) {
      _activeCount++;
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
    if (_activeCount > 0) {
      _activeCount--;
    }
    _drainWaiters();
  }

  void resize(int maxConcurrent) {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(
        maxConcurrent,
        'maxConcurrent',
        'must be greater than zero',
      );
    }
    _maxConcurrent = maxConcurrent;
    _drainWaiters();
  }

  void _drainWaiters() {
    while (_activeCount < _maxConcurrent && _waitQueue.isNotEmpty) {
      final waiter = _waitQueue.removeFirst();
      if (!waiter.isCompleted) {
        _activeCount++;
        waiter.complete();
      }
    }
  }
}
