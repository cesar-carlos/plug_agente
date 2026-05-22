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
}
