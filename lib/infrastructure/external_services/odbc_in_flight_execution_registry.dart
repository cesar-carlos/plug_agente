import 'dart:async';

/// Native ODBC handles for an in-flight SQL execution, keyed by request id.
final class OdbcInFlightExecutionHandle {
  const OdbcInFlightExecutionHandle({
    required this.connectionId,
    this.statementId,
    this.asyncRequestId,
  });

  final String connectionId;
  final int? statementId;
  final int? asyncRequestId;

  OdbcInFlightExecutionHandle copyWith({
    String? connectionId,
    int? statementId,
    int? asyncRequestId,
    bool clearStatementId = false,
    bool clearAsyncRequestId = false,
  }) {
    return OdbcInFlightExecutionHandle(
      connectionId: connectionId ?? this.connectionId,
      statementId: clearStatementId ? null : (statementId ?? this.statementId),
      asyncRequestId: clearAsyncRequestId ? null : (asyncRequestId ?? this.asyncRequestId),
    );
  }

  bool get hasNativeCancelTarget => statementId != null || asyncRequestId != null;
}

/// Default TTL for orphan pending aborts (ghost path armed before register/bind).
const Duration kOdbcPendingAbortTtl = Duration(minutes: 2);

/// Thread-safe registry of in-flight ODBC executions for cooperative / ghost abort.
///
/// When abort races ahead of handle registration, callers arm a pending abort via
/// [markPendingAbort]. Registration and native-target binds then notify
/// [setPendingAbortListener] so abort can run as soon as a handle exists.
/// Pending aborts expire after [pendingAbortTtl] to avoid orphan poison pills.
final class OdbcInFlightExecutionRegistry {
  OdbcInFlightExecutionRegistry({
    this.pendingAbortTtl = kOdbcPendingAbortTtl,
  });

  final Duration pendingAbortTtl;

  final Map<String, OdbcInFlightExecutionHandle> _active = <String, OdbcInFlightExecutionHandle>{};
  final Set<String> _pendingAborts = <String>{};
  final Map<String, Timer> _pendingAbortExpiryTimers = <String, Timer>{};
  void Function(String requestId)? _pendingAbortListener;

  OdbcInFlightExecutionHandle? peek(String requestId) => _active[requestId];

  bool hasPendingAbort(String requestId) => _pendingAborts.contains(requestId);

  void setPendingAbortListener(void Function(String requestId)? listener) {
    _pendingAbortListener = listener;
  }

  void markPendingAbort(String requestId) {
    if (requestId.isEmpty) {
      return;
    }
    final wasPending = _pendingAborts.contains(requestId);
    _pendingAborts.add(requestId);
    _armPendingAbortExpiry(requestId);
    // Notify only on first arm. Re-arming from abort-without-native-target must
    // not re-notify or fulfill loops forever while the handle still lacks a target.
    if (!wasPending && _active.containsKey(requestId)) {
      _notifyPendingAbort(requestId);
    }
  }

  void clearPendingAbort(String requestId) {
    if (requestId.isEmpty) {
      return;
    }
    _pendingAborts.remove(requestId);
    _cancelPendingAbortExpiry(requestId);
  }

  void register(String requestId, OdbcInFlightExecutionHandle handle) {
    if (requestId.isEmpty) {
      return;
    }
    _active[requestId] = handle;
    _notifyPendingAbort(requestId);
  }

  void bindStatement(String requestId, int statementId) {
    if (requestId.isEmpty) {
      return;
    }
    final existing = _active[requestId];
    if (existing == null) {
      return;
    }
    _active[requestId] = existing.copyWith(statementId: statementId);
    _notifyPendingAbort(requestId);
  }

  void bindAsyncRequest(String requestId, int asyncRequestId) {
    if (requestId.isEmpty) {
      return;
    }
    final existing = _active[requestId];
    if (existing == null) {
      return;
    }
    _active[requestId] = existing.copyWith(asyncRequestId: asyncRequestId);
    _notifyPendingAbort(requestId);
  }

  void unregister(String requestId) {
    if (requestId.isEmpty) {
      return;
    }
    _active.remove(requestId);
    clearPendingAbort(requestId);
  }

  void clearAll() {
    _active.clear();
    _pendingAborts.clear();
    for (final timer in _pendingAbortExpiryTimers.values) {
      timer.cancel();
    }
    _pendingAbortExpiryTimers.clear();
  }

  void _armPendingAbortExpiry(String requestId) {
    _cancelPendingAbortExpiry(requestId);
    if (pendingAbortTtl <= Duration.zero) {
      return;
    }
    _pendingAbortExpiryTimers[requestId] = Timer(pendingAbortTtl, () {
      _pendingAbortExpiryTimers.remove(requestId);
      _pendingAborts.remove(requestId);
    });
  }

  void _cancelPendingAbortExpiry(String requestId) {
    _pendingAbortExpiryTimers.remove(requestId)?.cancel();
  }

  void _notifyPendingAbort(String requestId) {
    if (!_pendingAborts.contains(requestId)) {
      return;
    }
    final listener = _pendingAbortListener;
    if (listener == null) {
      return;
    }
    // Defer so register/bind callers finish updating the handle before abort runs.
    scheduleMicrotask(() => listener(requestId));
  }
}

String odbcInFlightRegistryKey({
  required String requestId,
  String? sourceRpcRequestId,
}) {
  if (sourceRpcRequestId != null && sourceRpcRequestId.isNotEmpty) {
    return sourceRpcRequestId;
  }
  return requestId;
}
