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
}
