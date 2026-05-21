/// Stable outcome string values for JSON-RPC `agent.action.*` remote audit rows.
abstract final class AgentActionRemoteAuditConstants {
  /// Hub RPC accepted at the dispatcher boundary (append-only first row).
  static const String outcomeReceived = 'received';

  static const String outcomeSuccess = 'success';

  static const String outcomeRpcError = 'rpc_error';

  static const String outcomeAuthorizationDenied = 'authorization_denied';

  static const String outcomeNotificationRejected = 'notification_rejected';

  static const String outcomeRateLimited = 'rate_limited';

  /// Execution lifecycle row after a remote run is persisted as `queued`.
  static const String outcomeLifecycleEnqueued = 'lifecycle_enqueued';

  /// Execution lifecycle row after a remote run transitions to `running`.
  static const String outcomeLifecycleStarted = 'lifecycle_started';

  /// Execution lifecycle row when a remote cancel is accepted at the use case.
  static const String outcomeLifecycleCancelRequested = 'lifecycle_cancel_requested';

  /// Execution lifecycle row when a remote execution reaches a terminal status.
  static const String outcomeLifecycleFinished = 'lifecycle_finished';

  static const int listRecentDefaultLimit = 200;
  static const int listRecentMaxLimit = 500;

  static int clampListRecentLimit(int limit) {
    if (limit < 1) {
      return 1;
    }
    if (limit > listRecentMaxLimit) {
      return listRecentMaxLimit;
    }
    return limit;
  }
}
