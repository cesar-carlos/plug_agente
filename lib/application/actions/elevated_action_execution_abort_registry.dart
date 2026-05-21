import 'dart:async';

/// In-process abort signals for elevated executions awaiting helper status files.
class ElevatedActionExecutionAbortRegistry {
  final Map<String, Completer<void>> _abortCompletersByExecutionId = <String, Completer<void>>{};

  void register(String executionId) {
    final trimmedId = executionId.trim();
    if (trimmedId.isEmpty) {
      return;
    }

    final existing = _abortCompletersByExecutionId[trimmedId];
    if (existing != null && !existing.isCompleted) {
      return;
    }

    _abortCompletersByExecutionId[trimmedId] = Completer<void>();
  }

  void unregister(String executionId) {
    _abortCompletersByExecutionId.remove(executionId.trim());
  }

  Future<void> whenAborted(String executionId) {
    final completer = _abortCompletersByExecutionId[executionId.trim()];
    return completer?.future ?? Future<void>.value();
  }

  bool requestAbort(String executionId) {
    final completer = _abortCompletersByExecutionId[executionId.trim()];
    if (completer == null || completer.isCompleted) {
      return false;
    }

    completer.complete();
    return true;
  }
}
