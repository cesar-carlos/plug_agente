import 'package:plug_agente/domain/repositories/i_action_io_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';

final class ActionIoMetricsCollector implements IActionIoMetrics {
  ActionIoMetricsCollector(this._store);

  final MetricsEventStore _store;

  @override
  void recordExecutionOutcome(ActionIoExecutionOutcome outcome, {required bool captureComplete}) {
    _store.incrementEventCounter(switch (outcome) {
      ActionIoExecutionOutcome.succeeded => MetricsCounterNames.actionIoExecutionSucceeded,
      ActionIoExecutionOutcome.failed => MetricsCounterNames.actionIoExecutionFailed,
      ActionIoExecutionOutcome.cancelled => MetricsCounterNames.actionIoExecutionCancelled,
      ActionIoExecutionOutcome.unknown => MetricsCounterNames.actionIoExecutionUnknown,
    });
    _store.incrementEventCounter(
      captureComplete ? MetricsCounterNames.actionIoCaptureComplete : MetricsCounterNames.actionIoCaptureIncomplete,
    );
  }

  @override
  void recordInputOutcome(ActionIoInputOutcome outcome, {required int? confirmedBytes}) {
    _store.incrementEventCounter(switch (outcome) {
      ActionIoInputOutcome.written => MetricsCounterNames.actionIoInputWritten,
      ActionIoInputOutcome.failed => MetricsCounterNames.actionIoInputFailed,
      ActionIoInputOutcome.unknown => MetricsCounterNames.actionIoInputUnknown,
    });
    if (confirmedBytes == null) {
      _store.incrementEventCounter(MetricsCounterNames.actionIoInputUnknownProgress);
    } else {
      _store.incrementEventCounterBy(MetricsCounterNames.actionIoInputConfirmedBytes, confirmedBytes);
    }
  }

  @override
  void setQueueWaiting(int count) {
    if (count >= 0) _store.eventCounters[MetricsCounterNames.actionIoQueueWaiting] = count;
  }

  @override
  void setLifecycle({required int launches, required int sessions, required bool cleanupUnconfirmed}) {
    if (launches < 0 || sessions < 0) return;
    _store.eventCounters[MetricsCounterNames.actionIoLaunchesOwned] = launches;
    _store.eventCounters[MetricsCounterNames.actionIoSessionsOwned] = sessions;
    _store.eventCounters[MetricsCounterNames.actionIoCleanupUnconfirmed] = cleanupUnconfirmed ? 1 : 0;
  }

  @override
  void recordRemoteOutcome(ActionIoRemoteOutcome outcome) {
    _store.incrementEventCounter(MetricsCounterNames.actionIoRemoteCalls);
    _store.incrementEventCounter(switch (outcome) {
      ActionIoRemoteOutcome.success => MetricsCounterNames.actionIoRemoteSuccess,
      ActionIoRemoteOutcome.unauthorized => MetricsCounterNames.actionIoRemoteUnauthorized,
      ActionIoRemoteOutcome.limited => MetricsCounterNames.actionIoRemoteLimited,
      ActionIoRemoteOutcome.cancelled => MetricsCounterNames.actionIoRemoteCancelled,
      ActionIoRemoteOutcome.unknown => MetricsCounterNames.actionIoRemoteUnknown,
      ActionIoRemoteOutcome.failed => MetricsCounterNames.actionIoRemoteFailed,
    });
  }

  @override
  void setActiveReaders(int count) {
    if (count < 0) return;
    _store.eventCounters[MetricsCounterNames.actionIoReadersActive] = count;
    final previous = _store.counterValue(MetricsCounterNames.actionIoReadersPeak);
    if (count > previous) _store.eventCounters[MetricsCounterNames.actionIoReadersPeak] = count;
  }

  @override
  void recordReadBytes(int count) => _store.incrementEventCounterBy(MetricsCounterNames.actionIoReadBytes, count);

  @override
  void recordPersistedOutputBytes(int count) =>
      _store.incrementEventCounterBy(MetricsCounterNames.actionIoPersistedOutputBytes, count);

  @override
  void recordAdmittedInputBytes(int count) =>
      _store.incrementEventCounterBy(MetricsCounterNames.actionIoAdmittedInputBytes, count);

  @override
  void recordInterruptedExecutions(int count) =>
      _store.incrementEventCounterBy(MetricsCounterNames.actionIoInterruptedExecutions, count);
}
