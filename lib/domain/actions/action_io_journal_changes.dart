import 'dart:async';

/// A process-local hint. The journal remains the authority for delivery and ordering.
abstract interface class IActionIoJournalChanges {
  ActionIoJournalWaiter observeChanges(String executionId);
}

mixin ActionIoJournalChanges implements IActionIoJournalChanges {
  final _observers = <String, Set<ActionIoJournalWaiter>>{};

  @override
  ActionIoJournalWaiter observeChanges(String executionId) {
    final group = _observers.putIfAbsent(executionId, () => <ActionIoJournalWaiter>{});
    final waiter = ActionIoJournalWaiter._((observer) {
      group.remove(observer);
      if (group.isEmpty) _observers.remove(executionId);
    });
    group.add(waiter);
    return waiter;
  }

  void signalJournalCommit(String executionId) {
    final group = _observers[executionId];
    if (group == null) return;
    for (final waiter in group) {
      waiter._notify();
    }
  }
}

/// One waiting loop per observer. Coalesces commits, including a change between
/// checking the journal and entering the wait. Holds no bytes or credentials.
final class ActionIoJournalWaiter {
  ActionIoJournalWaiter._(this._detach);
  final void Function(ActionIoJournalWaiter) _detach;
  bool _closed = false;
  bool _changed = false;
  Completer<void>? _waiting;

  void _notify() {
    _changed = true;
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  Future<void> wait(Duration fallback) async {
    if (_closed) return;
    if (!_changed) {
      final waiting = Completer<void>();
      _waiting = waiting;
      try {
        await waiting.future.timeout(fallback, onTimeout: () {});
      } finally {
        _waiting = null;
      }
    }
    _changed = false;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _detach(this);
    _notify();
  }
}
