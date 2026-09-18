import 'dart:collection';

import 'dart:math' as math;

import 'package:plug_agente/infrastructure/metrics/metrics_duration_samples.dart';

/// Shared mutable metrics state used by domain collectors and the aggregator.
final class MetricsEventStore {
  MetricsEventStore({required int latencySampleCapacity, math.Random? random})
    : _latencySampleCapacity = latencySampleCapacity,
      _random = random {
    queueWaitTimes = _newDurationSamples();
    agentActionQueueWaitTimes = _newDurationSamples();
    agentActionExecutionDurations = _newDurationSamples();
    agentActionProcessStartDurations = _newDurationSamples();
    poolWaitTimes = _newDurationSamples();
    directConnectionWaitTimes = _newDurationSamples();
    readOnlyBatchParallelWaitTimes = _newDurationSamples();
    streamingWorkerHoldTimes = _newDurationSamples();
    connectTimes = _newDurationSamples();
    sqlExecutionTimes = _newDurationSamples();
    preparedPrepareTimes = _newDurationSamples();
    autoUpdateProbeTimes = _newDurationSamples();
    autoUpdateDownloadTimes = _newDurationSamples();
    outboundResponseWaitTimes = _newDurationSamples();
  }

  final int _latencySampleCapacity;
  final math.Random? _random;

  static const int maxRecentDiagnosticReasons = 50;

  final Map<String, int> eventCounters = <String, int>{};
  int activeDirectConnections = 0;
  int maxActiveDirectConnections = 0;
  int poolDiscardInflight = 0;
  int currentQueueSize = 0;
  int maxQueueSize = 0;
  int currentActiveWorkers = 0;
  int maxActiveWorkers = 0;
  int outboundResponseActive = 0;
  int outboundResponseMaxActive = 0;
  late final MetricsDurationSamples queueWaitTimes;
  late final MetricsDurationSamples agentActionQueueWaitTimes;
  late final MetricsDurationSamples agentActionExecutionDurations;
  late final MetricsDurationSamples agentActionProcessStartDurations;
  late final MetricsDurationSamples poolWaitTimes;
  late final MetricsDurationSamples directConnectionWaitTimes;
  late final MetricsDurationSamples readOnlyBatchParallelWaitTimes;
  late final MetricsDurationSamples streamingWorkerHoldTimes;
  late final MetricsDurationSamples connectTimes;
  late final MetricsDurationSamples sqlExecutionTimes;
  final Map<String, MetricsDurationSamples> sqlExecutionTimesByMode = <String, MetricsDurationSamples>{};
  final Map<String, ListQueue<DateTime>> sqlExecutionTimestampsByMode = <String, ListQueue<DateTime>>{};
  late final MetricsDurationSamples preparedPrepareTimes;
  final Map<String, int> streamingSkipReasons = <String, int>{};
  final Map<String, int> odbcNativeFallbackReasons = <String, int>{};
  final Map<String, int> odbcQueryTimeoutByStage = <String, int>{};
  final Map<String, int> schemaValidationDurationUsByKey = <String, int>{};
  final Map<String, int> schemaValidationCountByKey = <String, int>{};
  final Map<String, int> schemaValidationFailuresByKey = <String, int>{};
  int schemaValidationDurationUs = 0;
  int readOnlyBatchParallelLastRequested = 0;
  int readOnlyBatchParallelLastEffective = 0;
  final Queue<String> recentDiagnosticReasons = Queue<String>();
  late final MetricsDurationSamples autoUpdateProbeTimes;
  late final MetricsDurationSamples autoUpdateDownloadTimes;
  late final MetricsDurationSamples outboundResponseWaitTimes;

  int counterValue(String counter) => eventCounters[counter] ?? 0;

  void incrementEventCounter(String counter) => incrementEventCounterBy(counter, 1);

  void incrementEventCounterBy(String counter, int amount) {
    if (amount <= 0) {
      return;
    }
    eventCounters[counter] = (eventCounters[counter] ?? 0) + amount;
  }

  MetricsDurationSamples newDurationSamples() => _newDurationSamples();

  void recordDurationSample(MetricsDurationSamples samples, Duration value) => samples.add(value);

  void recordTimestampSample(ListQueue<DateTime> samples, DateTime value) {
    samples.addLast(value);
    if (samples.length > _latencySampleCapacity) {
      samples.removeFirst();
    }
  }

  MetricsDurationSamples _newDurationSamples() => MetricsDurationSamples(
    capacity: _latencySampleCapacity,
    random: _random,
  );

  void recordDiagnosticReason({
    required String category,
    required String reason,
  }) {
    final normalized = '${category.trim()}:${reason.trim()}';
    if (normalized == ':') {
      return;
    }
    recentDiagnosticReasons.addLast(normalized);
    while (recentDiagnosticReasons.length > maxRecentDiagnosticReasons) {
      recentDiagnosticReasons.removeFirst();
    }
  }

  void clearCountersAndSamples() {
    eventCounters.clear();
    activeDirectConnections = 0;
    maxActiveDirectConnections = 0;
    currentQueueSize = 0;
    maxQueueSize = 0;
    currentActiveWorkers = 0;
    maxActiveWorkers = 0;
    outboundResponseActive = 0;
    outboundResponseMaxActive = 0;
    queueWaitTimes.clear();
    autoUpdateProbeTimes.clear();
    autoUpdateDownloadTimes.clear();
    outboundResponseWaitTimes.clear();
    agentActionQueueWaitTimes.clear();
    agentActionExecutionDurations.clear();
    agentActionProcessStartDurations.clear();
    poolWaitTimes.clear();
    directConnectionWaitTimes.clear();
    readOnlyBatchParallelWaitTimes.clear();
    streamingWorkerHoldTimes.clear();
    connectTimes.clear();
    sqlExecutionTimes.clear();
    sqlExecutionTimesByMode.clear();
    sqlExecutionTimestampsByMode.clear();
    preparedPrepareTimes.clear();
    streamingSkipReasons.clear();
    odbcNativeFallbackReasons.clear();
    odbcQueryTimeoutByStage.clear();
    schemaValidationDurationUsByKey.clear();
    schemaValidationCountByKey.clear();
    schemaValidationFailuresByKey.clear();
    schemaValidationDurationUs = 0;
    readOnlyBatchParallelLastRequested = 0;
    readOnlyBatchParallelLastEffective = 0;
    recentDiagnosticReasons.clear();
  }
}
