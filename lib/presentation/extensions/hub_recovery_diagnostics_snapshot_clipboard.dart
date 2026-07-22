import 'package:plug_agente/domain/value_objects/hub_recovery_diagnostics_snapshot.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

extension HubRecoveryDiagnosticsSnapshotClipboard on HubRecoveryDiagnosticsSnapshot {
  String formattedForClipboard(AppLocalizations l10n) {
    String line(String label, String value) => '$label: ${value.isEmpty ? '—' : value}';

    return [
      line(l10n.diagnosticsHubRecoveryRecoveryId, recoveryId ?? ''),
      line(l10n.diagnosticsHubRecoveryConnectionStatus, connectionStatusName),
      line(l10n.diagnosticsHubRecoveryUiHint, hubRecoveryUiHintName),
      line(l10n.diagnosticsHubRecoveryConsecutiveFailures, '$consecutiveReconnectFailures'),
      line(l10n.diagnosticsHubRecoveryPersistentTick, '$persistentRetryTickCount'),
      line(l10n.diagnosticsHubRecoveryPersistentFailures, '$persistentFailureCount'),
      line(l10n.diagnosticsHubRecoveryPersistentUnreachableFailures, '$persistentUnreachableFailureCount'),
      line(l10n.diagnosticsHubRecoveryHardReloginAttempted, '$hardReloginAttemptedInCycle'),
      line(l10n.diagnosticsHubRecoveryLastError, lastError),
    ].join('\n');
  }
}
