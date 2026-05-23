import 'dart:async';

/// Serializes async work behind a FIFO mutex with epoch invalidation.
///
/// Each [runSerialized] call captures an epoch before waiting for the mutex.
/// [invalidateEpoch] bumps the epoch so waiters that acquire the mutex later
/// abort instead of running the supplied action callback.
class AsyncOperationGate {
  Future<void> _mutex = Future<void>.value();
  int _epoch = 0;

  int get epoch => _epoch;

  void invalidateEpoch() {
    _epoch++;
  }

  Future<T> runSerialized<T>(
    Future<T> Function() action, {
    T? staleResult,
    bool Function()? shouldAbort,
  }) async {
    final capturedEpoch = ++_epoch;
    final previous = _mutex;
    final release = Completer<void>();
    _mutex = release.future;
    try {
      await previous;
      if ((shouldAbort?.call() ?? false) || capturedEpoch != _epoch) {
        if (staleResult != null) {
          return staleResult;
        }
        throw StateError('Async operation epoch $capturedEpoch is stale (current $_epoch)');
      }
      return await action();
    } finally {
      release.complete();
    }
  }
}

/// Coalesces concurrent recovery handlers and runs them exclusively.
class ExclusiveRecoveryGate {
  Future<void> _mutex = Future<void>.value();
  bool _coalesced = false;

  Future<void> schedule({
    required Future<void> Function() handler,
    required bool Function() shouldAbort,
    required bool Function() shouldSkipAfterLock,
    void Function()? onCoalesced,
    void Function()? onSkippedAfterLock,
  }) async {
    if (shouldAbort()) {
      return;
    }
    if (_coalesced) {
      onCoalesced?.call();
      return;
    }
    _coalesced = true;
    final previous = _mutex;
    final release = Completer<void>();
    _mutex = release.future;
    try {
      await previous;
      if (shouldAbort()) {
        return;
      }
      if (shouldSkipAfterLock()) {
        onSkippedAfterLock?.call();
        return;
      }
      await handler();
    } finally {
      _coalesced = false;
      release.complete();
    }
  }
}
