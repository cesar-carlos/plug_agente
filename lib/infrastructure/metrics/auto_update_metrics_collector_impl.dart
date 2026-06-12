import 'package:plug_agente/domain/repositories/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';

final class AutoUpdateMetricsCollectorImpl implements IAutoUpdateMetricsCollector {
  AutoUpdateMetricsCollectorImpl(this._store);

  final MetricsEventStore _store;

  int get manualCheckStartedCount => _store.counterValue(MetricsCounterNames.autoUpdateManualCheckStartedCounter);
  int get manualCheckSuccessAvailableCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateManualCheckSuccessAvailableCounter);
  int get manualCheckSuccessNotAvailableCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateManualCheckSuccessNotAvailableCounter);
  int get manualCheckUpdaterErrorCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateManualCheckUpdaterErrorCounter);
  int get manualCheckTriggerTimeoutCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateManualCheckTriggerTimeoutCounter);
  int get manualCheckCompletionTimeoutCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateManualCheckCompletionTimeoutCounter);
  int get manualCheckTriggerFailureCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateManualCheckTriggerFailureCounter);
  int get manualCheckNotInitializedCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateManualCheckNotInitializedCounter);
  int get circuitOpenedCount => _store.counterValue(MetricsCounterNames.autoUpdateCircuitOpenedCounter);
  int get circuitOpenRejectedCount => _store.counterValue(MetricsCounterNames.autoUpdateCircuitOpenRejectedCounter);
  int get backgroundCheckTriggerFailureCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateBackgroundCheckTriggerFailureCounter);
  int get backgroundCheckUpdaterErrorCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateBackgroundCheckUpdaterErrorCounter);
  int get awaitingUserConsentCount => _store.counterValue(MetricsCounterNames.autoUpdateAwaitingUserConsentCounter);
  int get userInitiatedApplySuccessCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateUserInitiatedApplySuccessCounter);
  int get userInitiatedApplyFailureCount =>
      _store.counterValue(MetricsCounterNames.autoUpdateUserInitiatedApplyFailureCounter);

  @override
  void recordAutoUpdateManualCheckStarted() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateManualCheckStartedCounter);
  }

  @override
  void recordAutoUpdateManualCheckSuccessAvailable() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateManualCheckSuccessAvailableCounter);
  }

  @override
  void recordAutoUpdateManualCheckSuccessNotAvailable() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateManualCheckSuccessNotAvailableCounter);
  }

  @override
  void recordAutoUpdateManualCheckUpdaterError() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateManualCheckUpdaterErrorCounter);
  }

  @override
  void recordAutoUpdateManualCheckTriggerTimeout() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateManualCheckTriggerTimeoutCounter);
  }

  @override
  void recordAutoUpdateManualCheckCompletionTimeout() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateManualCheckCompletionTimeoutCounter);
  }

  @override
  void recordAutoUpdateManualCheckTriggerFailure() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateManualCheckTriggerFailureCounter);
  }

  @override
  void recordAutoUpdateManualCheckNotInitialized() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateManualCheckNotInitializedCounter);
  }

  @override
  void recordAutoUpdateCircuitOpened() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateCircuitOpenedCounter);
  }

  @override
  void recordAutoUpdateCircuitOpenRejected() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateCircuitOpenRejectedCounter);
  }

  @override
  void recordAutoUpdateBackgroundCheckTriggerFailure() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateBackgroundCheckTriggerFailureCounter);
  }

  @override
  void recordAutoUpdateBackgroundCheckUpdaterError() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateBackgroundCheckUpdaterErrorCounter);
  }

  @override
  void recordAutoUpdateProbeDuration(Duration duration) {
    if (duration.isNegative) {
      return;
    }
    _store.recordDurationSample(_store.autoUpdateProbeTimes, duration);
  }

  @override
  void recordAutoUpdateDownloadDuration(Duration duration) {
    if (duration.isNegative) {
      return;
    }
    _store.recordDurationSample(_store.autoUpdateDownloadTimes, duration);
  }

  @override
  void recordAutoUpdateAwaitingUserConsent() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateAwaitingUserConsentCounter);
  }

  @override
  void recordAutoUpdateUserInitiatedApplySuccess() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateUserInitiatedApplySuccessCounter);
  }

  @override
  void recordAutoUpdateUserInitiatedApplyFailure() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateUserInitiatedApplyFailureCounter);
  }

  @override
  void recordAutoUpdateNotificationsPreferenceEnabled() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateNotificationsPreferenceEnabledCounter);
  }

  @override
  void recordAutoUpdateNotificationsPreferenceDisabled() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateNotificationsPreferenceDisabledCounter);
  }

  @override
  void recordAutoUpdateAutomaticSilentPreferenceEnabled() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateAutomaticSilentPreferenceEnabledCounter);
  }

  @override
  void recordAutoUpdateAutomaticSilentPreferenceDisabled() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateAutomaticSilentPreferenceDisabledCounter);
  }

  @override
  void recordAutoUpdateManualOnlyModeApplied() {
    _store.incrementEventCounter(MetricsCounterNames.autoUpdateManualOnlyModeAppliedCounter);
  }
}
