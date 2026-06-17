/// Hub reconnect, persistent retry, and HTTP resilience limits.
abstract final class HubResilienceConstants {
  HubResilienceConstants._();

  /// Hub `GET /api/v1/agents` during backup restore staging (duplicate-session check).
  static const Duration backupRestoreAgentsListTimeout = Duration(seconds: 15);

  /// Hub agent profile PATCH/GET (`/api/v1/agents/{id}/profile`).
  static const Duration agentHubProfileHttpTimeout = Duration(seconds: 30);

  /// App-level burst reconnect attempts (ConnectionProvider) after
  /// [socketReconnectionAttempts] is exhausted. Distinct from
  /// [socketReconnectionAttempts] which is the Socket.IO client internal limit.
  static const int defaultHubRecoveryBurstMaxAttempts = 3;

  /// Interval between automatic hub reconnect attempts after the burst is exhausted.
  static const Duration hubPersistentRetryInterval = Duration(seconds: 45);

  /// Minimum spacing between automatic hard relogin attempts during **persistent**
  /// hub retry. Burst escalation and proactive pre-socket relogin ignore this cooldown.
  static const Duration hubHardReloginCooldown = Duration(seconds: 60);

  /// Max failed persistent reconnect ticks before giving up (`0` = unlimited).
  static const int hubPersistentRetryMaxFailedTicks = 0;

  /// User-facing message when [hubPersistentRetryMaxFailedTicks] is exceeded (English;
  /// mirror in ARB for localized surfaces).
  static const String hubPersistentRetryExhaustedMessage =
      'Could not reach the hub after many attempts. Check the server URL, network, and '
      'sign-in, then tap Connect.';

  /// Legacy name; same as [defaultHubRecoveryBurstMaxAttempts] (ODBC pool options).
  static const int defaultMaxReconnectAttempts = defaultHubRecoveryBurstMaxAttempts;

  /// Socket.IO client internal reconnection attempts (transport-level).
  static const int socketReconnectionAttempts = 15;
  static const int socketReconnectionDelayMs = 5000;
  static const int socketReconnectionDelayMaxMs = 60000;

  /// Minimum wall-clock interval between HTTP token refresh attempts during hub
  /// recovery (reduces auth endpoint load when the transport is still failing).
  static const Duration hubTokenRefreshMinInterval = Duration(seconds: 5);

  /// Refresh hub access JWT this long before JWT `exp` (server default ~4h).
  static const Duration hubAccessTokenProactiveRefreshMargin = Duration(minutes: 10);

  /// When hub reconnect logs omit user-facing error text (`recordErrorMessage: false`),
  /// emit a warning every N failures to avoid log storms during persistent retry.
  static const int hubReconnectFailureLogThrottleStride = 10;

  /// Log hub reachability probes that exceed this duration (diagnostics).
  static const int hubAvailabilityProbeSlowLogThresholdMs = 1000;
}
