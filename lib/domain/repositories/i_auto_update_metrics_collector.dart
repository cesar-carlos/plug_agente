/// Metrics surface for the **manual** auto-update path (Settings ->
/// "Check for updates"). Lives apart from the other surfaces so a test
/// stub or a feature-specific consumer can implement only what it needs.
abstract interface class IAutoUpdateManualCheckMetricsCollector {
  void recordAutoUpdateManualCheckStarted();
  void recordAutoUpdateManualCheckSuccessAvailable();
  void recordAutoUpdateManualCheckSuccessNotAvailable();
  void recordAutoUpdateManualCheckUpdaterError();
  void recordAutoUpdateManualCheckTriggerTimeout();
  void recordAutoUpdateManualCheckCompletionTimeout();
  void recordAutoUpdateManualCheckTriggerFailure();
  void recordAutoUpdateManualCheckNotInitialized();

  /// Manual-path circuit breaker opened after repeated timeouts.
  void recordAutoUpdateCircuitOpened();

  /// Manual-path check rejected because the timeout circuit is still
  /// open.
  void recordAutoUpdateCircuitOpenRejected();
}

/// Metrics surface for the **background** auto-update path (WinSparkle
/// periodic trigger).
abstract interface class IAutoUpdateBackgroundCheckMetricsCollector {
  void recordAutoUpdateBackgroundCheckTriggerFailure();
  void recordAutoUpdateBackgroundCheckUpdaterError();
}

/// Metrics surface for the **silent** auto-update path (probe -> download
/// -> stage -> apply). Includes the user-initiated apply path so the
/// banner conversion KPIs travel together with the consent gate.
abstract interface class IAutoUpdateSilentMetricsCollector {
  /// Adds a duration sample for the appcast probe step (HTTP fetch +
  /// parse). Used to expose `auto_update_probe_*_time_ms` percentiles
  /// in the metrics snapshot.
  void recordAutoUpdateProbeDuration(Duration duration);

  /// Adds a duration sample for the asset download step (network +
  /// SHA-256 hashing). Captured when the install path completes
  /// successfully.
  void recordAutoUpdateDownloadDuration(Duration duration);

  /// Probe found a new version but the silent flow stopped before
  /// downloading because Windows UAC would prompt the user. Used to
  /// dimension how often the gate triggers and feed conversion analysis
  /// against the apply counters below.
  void recordAutoUpdateAwaitingUserConsent();

  /// Operator clicked "Download and install" in the in-app banner and
  /// the full user-initiated flow finished successfully (downloaded,
  /// staged, helper launched).
  void recordAutoUpdateUserInitiatedApplySuccess();

  /// Operator clicked "Download and install" but the user-initiated
  /// flow could not produce a ready installer (network error, cooldown,
  /// cancelled, etc.).
  void recordAutoUpdateUserInitiatedApplyFailure();

  /// Automatic silent flow applied a staged update without operator
  /// confirmation (download finished and auto-apply succeeded).
  void recordAutoUpdateAutomaticApplySuccess();

  /// Automatic silent flow attempted auto-apply after staging but the
  /// helper launch or pre-close step failed.
  void recordAutoUpdateAutomaticApplyFailure();
}

/// Operator preference changes from Settings (notifications, silent
/// install, manual-only preset).
abstract interface class IAutoUpdatePreferenceMetricsCollector {
  void recordAutoUpdateNotificationsPreferenceEnabled();
  void recordAutoUpdateNotificationsPreferenceDisabled();
  void recordAutoUpdateAutomaticSilentPreferenceEnabled();
  void recordAutoUpdateAutomaticSilentPreferenceDisabled();
  void recordAutoUpdateManualOnlyModeApplied();
}

/// Aggregate facade that bundles every auto-update metric surface. Kept
/// as the primary type the application layer asks for, so production
/// wiring stays a single dependency while consumers that only need a
/// slice (e.g., the orchestrator only emits manual + background events,
/// the coordinator only emits silent events) can ask for the narrower
/// interface.
abstract interface class IAutoUpdateMetricsCollector
    implements
        IAutoUpdateManualCheckMetricsCollector,
        IAutoUpdateBackgroundCheckMetricsCollector,
        IAutoUpdateSilentMetricsCollector,
        IAutoUpdatePreferenceMetricsCollector {}
