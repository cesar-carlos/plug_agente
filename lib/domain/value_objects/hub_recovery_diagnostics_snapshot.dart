/// Read-only hub recovery fields for diagnostics / support surfaces.
class HubRecoveryDiagnosticsSnapshot {
  const HubRecoveryDiagnosticsSnapshot({
    required this.recoveryId,
    required this.connectionStatusName,
    required this.hubRecoveryUiHintName,
    required this.consecutiveReconnectFailures,
    required this.persistentRetryTickCount,
    required this.persistentFailureCount,
    required this.hardReloginAttemptedInCycle,
    required this.lastError,
  });

  final String? recoveryId;
  final String connectionStatusName;
  final String hubRecoveryUiHintName;
  final int consecutiveReconnectFailures;
  final int persistentRetryTickCount;
  final int persistentFailureCount;
  final bool hardReloginAttemptedInCycle;
  final String lastError;
}
