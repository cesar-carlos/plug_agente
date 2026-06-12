import 'dart:collection';

/// Shared mutable metrics state used by domain collectors and the aggregator.
final class MetricsEventStore {
  static const int maxWaitTimeSamples = 1000;
  static const int maxRecentDiagnosticReasons = 50;

  final Map<String, int> eventCounters = <String, int>{};
  int activeDirectConnections = 0;
  int maxActiveDirectConnections = 0;
  int poolDiscardInflight = 0;
  int currentQueueSize = 0;
  int maxQueueSize = 0;
  int currentActiveWorkers = 0;
  int maxActiveWorkers = 0;
  final ListQueue<Duration> queueWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> agentActionQueueWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> agentActionExecutionDurations = ListQueue<Duration>();
  final ListQueue<Duration> poolWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> directConnectionWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> readOnlyBatchParallelWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> streamingWorkerHoldTimes = ListQueue<Duration>();
  final ListQueue<Duration> connectTimes = ListQueue<Duration>();
  final ListQueue<Duration> sqlExecutionTimes = ListQueue<Duration>();
  final Map<String, ListQueue<Duration>> sqlExecutionTimesByMode = <String, ListQueue<Duration>>{};
  final Map<String, ListQueue<DateTime>> sqlExecutionTimestampsByMode = <String, ListQueue<DateTime>>{};
  final ListQueue<Duration> preparedPrepareTimes = ListQueue<Duration>();
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
  final ListQueue<Duration> autoUpdateProbeTimes = ListQueue<Duration>();
  final ListQueue<Duration> autoUpdateDownloadTimes = ListQueue<Duration>();

  int counterValue(String counter) => eventCounters[counter] ?? 0;

  void incrementEventCounter(String counter) => incrementEventCounterBy(counter, 1);

  void incrementEventCounterBy(String counter, int amount) {
    if (amount <= 0) {
      return;
    }
    eventCounters[counter] = (eventCounters[counter] ?? 0) + amount;
  }

  void recordDurationSample(ListQueue<Duration> samples, Duration value) {
    samples.addLast(value);
    if (samples.length > maxWaitTimeSamples) {
      samples.removeFirst();
    }
  }

  void recordTimestampSample(ListQueue<DateTime> samples, DateTime value) {
    samples.addLast(value);
    if (samples.length > maxWaitTimeSamples) {
      samples.removeFirst();
    }
  }

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
    queueWaitTimes.clear();
    autoUpdateProbeTimes.clear();
    autoUpdateDownloadTimes.clear();
    agentActionQueueWaitTimes.clear();
    agentActionExecutionDurations.clear();
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
