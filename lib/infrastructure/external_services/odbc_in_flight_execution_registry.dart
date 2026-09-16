import 'dart:async';

/// Native ODBC handles for one physical execution owned by an RPC request.
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
/// A single RPC can own several physical executions (notably a parallel batch).
/// Handles are therefore indexed by both owner request and execution id. When an
/// abort races ahead of registration, callers arm it for the owner via
/// [markPendingAbort]. Registration and native-target binds then notify
/// [setPendingAbortListener] so abort can run as soon as a handle exists.
/// Pending aborts expire after [pendingAbortTtl] to avoid orphan poison pills.
final class OdbcInFlightExecutionRegistry {
  OdbcInFlightExecutionRegistry({
    this.pendingAbortTtl = kOdbcPendingAbortTtl,
  });

  final Duration pendingAbortTtl;

  final Map<String, Map<String, OdbcInFlightExecutionHandle>> _active =
      <String, Map<String, OdbcInFlightExecutionHandle>>{};
  final Set<String> _pendingAborts = <String>{};
  final Set<String> _ownerAborts = <String>{};
  final Map<String, Timer> _pendingAbortExpiryTimers = <String, Timer>{};
  void Function(String requestId)? _pendingAbortListener;

  /// Compatibility lookup for callers that only need to know whether the
  /// owner has a cancel target. New code should use [peekAll].
  OdbcInFlightExecutionHandle? peek(String requestId) {
    final executions = _active[requestId];
    if (executions == null || executions.isEmpty) {
      return null;
    }
    return executions.values.first;
  }

  List<OdbcInFlightExecutionHandle> peekAll(String requestId) {
    final executions = _active[requestId];
    if (executions == null || executions.isEmpty) {
      return const <OdbcInFlightExecutionHandle>[];
    }
    return List<OdbcInFlightExecutionHandle>.unmodifiable(executions.values);
  }

  bool hasPendingAbort(String requestId) => _pendingAborts.contains(requestId);

  bool hasOwnerAbort(String requestId) => _ownerAborts.contains(requestId);

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
    if (!wasPending && (_active[requestId]?.isNotEmpty ?? false)) {
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

  /// Keeps an active owner's cancellation armed while parallel children are
  /// registered. This differs from [markPendingAbort], whose TTL models only
  /// the pre-registration ghost race.
  void markOwnerAbort(String requestId) {
    if (requestId.isEmpty) {
      return;
    }
    final wasArmed = _ownerAborts.contains(requestId);
    _ownerAborts.add(requestId);
    if (!wasArmed) {
      _notifyPendingAbort(requestId);
    }
  }

  void register(
    String requestId,
    OdbcInFlightExecutionHandle handle, {
    String? executionId,
  }) {
    if (requestId.isEmpty) {
      return;
    }
    final effectiveExecutionId = executionId?.isNotEmpty == true ? executionId! : requestId;
    _active.putIfAbsent(requestId, () => <String, OdbcInFlightExecutionHandle>{})[effectiveExecutionId] = handle;
    _notifyPendingAbort(requestId);
  }

  void bindStatement(
    String requestId,
    int statementId, {
    String? executionId,
  }) {
    if (requestId.isEmpty) {
      return;
    }
    final executions = _active[requestId];
    final effectiveExecutionId = executionId?.isNotEmpty == true ? executionId! : requestId;
    final existing = executions?[effectiveExecutionId];
    if (existing == null) {
      return;
    }
    executions![effectiveExecutionId] = existing.copyWith(statementId: statementId);
    _notifyPendingAbort(requestId);
  }

  void bindAsyncRequest(
    String requestId,
    int asyncRequestId, {
    String? executionId,
  }) {
    if (requestId.isEmpty) {
      return;
    }
    final executions = _active[requestId];
    final effectiveExecutionId = executionId?.isNotEmpty == true ? executionId! : requestId;
    final existing = executions?[effectiveExecutionId];
    if (existing == null) {
      return;
    }
    executions![effectiveExecutionId] = existing.copyWith(asyncRequestId: asyncRequestId);
    _notifyPendingAbort(requestId);
  }

  void unregister(String requestId, {String? executionId}) {
    if (requestId.isEmpty) {
      return;
    }
    if (executionId == null || executionId.isEmpty) {
      _active.remove(requestId);
      clearPendingAbort(requestId);
      _ownerAborts.remove(requestId);
      return;
    }
    final executions = _active[requestId];
    executions?.remove(executionId);
    if (executions?.isEmpty ?? false) {
      _active.remove(requestId);
      clearPendingAbort(requestId);
      _ownerAborts.remove(requestId);
    }
  }

  void clearAll() {
    _active.clear();
    _pendingAborts.clear();
    _ownerAborts.clear();
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
    if (!_pendingAborts.contains(requestId) && !_ownerAborts.contains(requestId)) {
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

/// A unique physical execution id must never be replaced by the outer RPC id.
String odbcInFlightExecutionId({required String requestId}) => requestId;
