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

/// Thread-safe registry of in-flight ODBC executions for cooperative / ghost abort.
final class OdbcInFlightExecutionRegistry {
  final Map<String, OdbcInFlightExecutionHandle> _active = <String, OdbcInFlightExecutionHandle>{};

  OdbcInFlightExecutionHandle? peek(String requestId) => _active[requestId];

  void register(String requestId, OdbcInFlightExecutionHandle handle) {
    if (requestId.isEmpty) {
      return;
    }
    _active[requestId] = handle;
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
  }

  void unregister(String requestId) {
    if (requestId.isEmpty) {
      return;
    }
    _active.remove(requestId);
  }

  void clearAll() => _active.clear();
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
