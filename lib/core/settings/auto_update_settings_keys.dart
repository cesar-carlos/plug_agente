/// Persistence keys for auto-update runtime state (diagnostics, cooldowns,
/// pending silent updates). Distinct from `AppSettingsKeys`, which holds
/// operator-facing preference toggles under the `settings.*` namespace.
class AutoUpdateSettingsKeys {
  AutoUpdateSettingsKeys._();

  static const String lastManualDiagnostics = 'auto_update.last_manual_diagnostics';
  static const String lastBackgroundDiagnostics = 'auto_update.last_background_diagnostics';
  static const String timeoutConsecutiveCount = 'auto_update.timeout_consecutive_count';
  static const String timeoutCooldownUntilMs = 'auto_update.timeout_cooldown_until_ms';

  static const String lastAutomaticDiagnostics = 'auto_update.last_automatic_diagnostics';
  static const String automaticFailureCount = 'auto_update.automatic_failure_count';
  static const String automaticCooldownUntilMs = 'auto_update.automatic_cooldown_until_ms';
  static const String rolloutBucket = 'auto_update.rollout_bucket';

  static const String pendingSilentUpdate = 'auto_update.pending_silent_update';
  static const String recentCheckIds = 'auto_update.recent_check_ids';
}
