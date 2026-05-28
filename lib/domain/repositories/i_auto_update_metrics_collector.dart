abstract class IAutoUpdateMetricsCollector {
  void recordAutoUpdateBackgroundCheckTriggerFailure();

  void recordAutoUpdateBackgroundCheckUpdaterError();

  void recordAutoUpdateCircuitOpened();

  void recordAutoUpdateCircuitOpenRejected();

  void recordAutoUpdateManualCheckCompletionTimeout();

  void recordAutoUpdateManualCheckNotInitialized();

  void recordAutoUpdateManualCheckStarted();

  void recordAutoUpdateManualCheckSuccessAvailable();

  void recordAutoUpdateManualCheckSuccessNotAvailable();

  void recordAutoUpdateManualCheckTriggerFailure();

  void recordAutoUpdateManualCheckTriggerTimeout();

  void recordAutoUpdateManualCheckUpdaterError();

  /// Adds a duration sample for the appcast probe step (HTTP fetch + parse).
  /// Used to expose `auto_update_probe_*_time_ms` percentiles in the metrics
  /// snapshot.
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
}
