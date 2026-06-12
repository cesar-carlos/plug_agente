import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_diagnostics_constants.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/repositories/action_execution_queue_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_schema_validation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/action_execution_queue_metrics_collector_impl.dart';
import 'package:plug_agente/infrastructure/metrics/agent_action_execution_metrics_collector_impl.dart';
import 'package:plug_agente/infrastructure/metrics/auto_update_metrics_collector_impl.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector_snapshot_builder.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';
import 'package:plug_agente/infrastructure/metrics/sql_execution_queue_metrics_collector_impl.dart';

export 'metrics_counter_constants.dart';

part 'metrics_collector_auth_domain.dart';
part 'metrics_collector_odbc_domain.dart';
part 'metrics_collector_protocol_domain.dart';

/// Aggregates domain metrics collectors and exposes a stable export surface.
final class MetricsCollector extends MetricsCollectorCore
    with MetricsCollectorAuthDomain, MetricsCollectorOdbcDomain, MetricsCollectorProtocolDomain
    implements
        IMetricsCollector,
        IAutoUpdateMetricsCollector,
        ISchemaValidationMetricsCollector,
        SqlExecutionQueueMetricsCollector,
        ActionExecutionQueueMetricsCollector,
        AgentActionExecutionMetricsCollector {
  MetricsCollector() {
    sqlQueueMetrics = SqlExecutionQueueMetricsCollectorImpl(store);
    actionQueueMetrics = ActionExecutionQueueMetricsCollectorImpl(store);
    agentActionMetrics = AgentActionExecutionMetricsCollectorImpl(store);
    autoUpdateMetrics = AutoUpdateMetricsCollectorImpl(store);
  }
}

/// Query metrics ring buffer and shared event store for domain collectors.
class MetricsCollectorCore {
  MetricsCollectorCore();

  static const int _maxMetrics = 10000;

  final MetricsEventStore store = MetricsEventStore();

  late final SqlExecutionQueueMetricsCollectorImpl sqlQueueMetrics;
  late final ActionExecutionQueueMetricsCollectorImpl actionQueueMetrics;
  late final AgentActionExecutionMetricsCollectorImpl agentActionMetrics;
  late final AutoUpdateMetricsCollectorImpl autoUpdateMetrics;

  final ListQueue<QueryMetrics> _metrics = ListQueue<QueryMetrics>();
  final _metricsController = StreamController<QueryMetrics>.broadcast();

  Stream<QueryMetrics> get metricsStream => _metricsController.stream;

  List<QueryMetrics> get metrics => List.unmodifiable(_metrics);

  int get count => _metrics.length;

  int get sqlQueueRejectionCount => sqlQueueMetrics.rejectionCount;
  int get sqlQueueTimeoutCount => sqlQueueMetrics.timeoutCount;
  int get sqlQueueTimeoutAfterWorkerStartedCount => sqlQueueMetrics.timeoutAfterWorkerStartedCount;
  int get sqlQueueSaturation70Count => sqlQueueMetrics.saturation70Count;
  int get sqlQueueSaturation90Count => sqlQueueMetrics.saturation90Count;
  int get sqlQueueWorkersEqualPoolCount => sqlQueueMetrics.workersEqualPoolCount;

  int get autoUpdateManualCheckStartedCount => autoUpdateMetrics.manualCheckStartedCount;
  int get autoUpdateManualCheckSuccessAvailableCount => autoUpdateMetrics.manualCheckSuccessAvailableCount;
  int get autoUpdateManualCheckSuccessNotAvailableCount => autoUpdateMetrics.manualCheckSuccessNotAvailableCount;
  int get autoUpdateManualCheckUpdaterErrorCount => autoUpdateMetrics.manualCheckUpdaterErrorCount;
  int get autoUpdateManualCheckTriggerTimeoutCount => autoUpdateMetrics.manualCheckTriggerTimeoutCount;
  int get autoUpdateManualCheckCompletionTimeoutCount => autoUpdateMetrics.manualCheckCompletionTimeoutCount;
  int get autoUpdateManualCheckTriggerFailureCount => autoUpdateMetrics.manualCheckTriggerFailureCount;
  int get autoUpdateManualCheckNotInitializedCount => autoUpdateMetrics.manualCheckNotInitializedCount;
  int get autoUpdateCircuitOpenedCount => autoUpdateMetrics.circuitOpenedCount;
  int get autoUpdateCircuitOpenRejectedCount => autoUpdateMetrics.circuitOpenRejectedCount;
  int get autoUpdateBackgroundCheckTriggerFailureCount => autoUpdateMetrics.backgroundCheckTriggerFailureCount;
  int get autoUpdateBackgroundCheckUpdaterErrorCount => autoUpdateMetrics.backgroundCheckUpdaterErrorCount;
  int get autoUpdateAwaitingUserConsentCount => autoUpdateMetrics.awaitingUserConsentCount;
  int get autoUpdateUserInitiatedApplySuccessCount => autoUpdateMetrics.userInitiatedApplySuccessCount;
  int get autoUpdateUserInitiatedApplyFailureCount => autoUpdateMetrics.userInitiatedApplyFailureCount;

  int get currentQueueSize => store.currentQueueSize;
  int get maxQueueSize => store.maxQueueSize;
  int get currentActiveWorkers => store.currentActiveWorkers;
  int get maxActiveWorkers => store.maxActiveWorkers;

  Duration? get averageQueueWaitTime {
    if (store.queueWaitTimes.isEmpty) return null;
    final totalMs = store.queueWaitTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ store.queueWaitTimes.length);
  }

  Duration? get p95QueueWaitTime {
    if (store.queueWaitTimes.isEmpty) return null;
    final waitTimes = _sortedQueueWaitTimesMs();
    return Duration(milliseconds: waitTimes[(waitTimes.length * 0.95).floor()]);
  }

  Duration? get maxRecentQueueWaitTime {
    if (store.queueWaitTimes.isEmpty) return null;
    final waitTimes = _sortedQueueWaitTimesMs();
    return Duration(milliseconds: waitTimes.last);
  }

  Map<String, int> get eventCounters => UnmodifiableMapView<String, int>(store.eventCounters);

  void clear() {
    _metrics.clear();
    store.clearCountersAndSamples();
  }

  void recordQueueAdded(int currentSize) => sqlQueueMetrics.recordQueueAdded(currentSize);

  void recordQueueSizeChanged(int currentSize) => sqlQueueMetrics.recordQueueSizeChanged(currentSize);

  void recordQueueRejection() => sqlQueueMetrics.recordQueueRejection();

  void recordQueueTimeout() => sqlQueueMetrics.recordQueueTimeout();

  void recordQueueTimeoutAfterWorkerStarted() => sqlQueueMetrics.recordQueueTimeoutAfterWorkerStarted();

  void recordQueueSaturation({
    required int thresholdPercent,
    required int currentSize,
    required int maxSize,
  }) =>
      sqlQueueMetrics.recordQueueSaturation(
        thresholdPercent: thresholdPercent,
        currentSize: currentSize,
        maxSize: maxSize,
      );

  void recordQueueWaitTime(Duration waitTime) => sqlQueueMetrics.recordQueueWaitTime(waitTime);

  void recordConcurrencyReject() => actionQueueMetrics.recordConcurrencyReject();

  void recordConcurrencyIgnore() => actionQueueMetrics.recordConcurrencyIgnore();

  void recordQueueDepthFull() => actionQueueMetrics.recordQueueDepthFull();

  void recordPendingEnqueued() => actionQueueMetrics.recordPendingEnqueued();

  void recordIdempotentReplay() => actionQueueMetrics.recordIdempotentReplay();

  void recordRunStarted() => actionQueueMetrics.recordRunStarted();

  void recordPendingWaitTimeout() => actionQueueMetrics.recordPendingWaitTimeout();

  void recordPendingCancelled() => actionQueueMetrics.recordPendingCancelled();

  void recordPendingDequeueWaitTime(Duration wait) => actionQueueMetrics.recordPendingDequeueWaitTime(wait);

  void recordTerminalOutcome(AgentActionExecutionStatus status) =>
      agentActionMetrics.recordTerminalOutcome(status);

  void recordExecutionDuration(Duration duration) => agentActionMetrics.recordExecutionDuration(duration);

  void recordRemotePermissionDenied() => agentActionMetrics.recordRemotePermissionDenied();

  void recordLocalAuthorizationDenied() => agentActionMetrics.recordLocalAuthorizationDenied();

  void recordRemoteRateLimited() => agentActionMetrics.recordRemoteRateLimited();

  void recordExecutionHistoryPurge(int removedCount) => agentActionMetrics.recordExecutionHistoryPurge(removedCount);

  void recordRemoteAuditPurge(int removedCount) => agentActionMetrics.recordRemoteAuditPurge(removedCount);

  void recordRpcIdempotencyCachePurge(int removedCount) =>
      agentActionMetrics.recordRpcIdempotencyCachePurge(removedCount);

  void recordElevatedBridgeArtifactsPurge(int removedCount) =>
      agentActionMetrics.recordElevatedBridgeArtifactsPurge(removedCount);

  void recordRemoteAuditExecutionCorrelated() => agentActionMetrics.recordRemoteAuditExecutionCorrelated();

  void recordCancelKillFailed() => agentActionMetrics.recordCancelKillFailed();

  void recordCancelKillPermissionDenied() => agentActionMetrics.recordCancelKillPermissionDenied();

  void recordCancelProcessNotActive() => agentActionMetrics.recordCancelProcessNotActive();

  void recordCancelProcessIdMismatch() => agentActionMetrics.recordCancelProcessIdMismatch();

  void recordCancelProcessIdentityMismatch() => agentActionMetrics.recordCancelProcessIdentityMismatch();

  void recordCancelProcessIdentityUnavailable() => agentActionMetrics.recordCancelProcessIdentityUnavailable();

  void recordCapturedOutputPersisted({
    required bool stdoutCaptured,
    required bool stderrCaptured,
    required bool stdoutTruncated,
    required bool stderrTruncated,
    int stdoutUtf8Bytes = 0,
    int stderrUtf8Bytes = 0,
  }) =>
      agentActionMetrics.recordCapturedOutputPersisted(
        stdoutCaptured: stdoutCaptured,
        stderrCaptured: stderrCaptured,
        stdoutTruncated: stdoutTruncated,
        stderrTruncated: stderrTruncated,
        stdoutUtf8Bytes: stdoutUtf8Bytes,
        stderrUtf8Bytes: stderrUtf8Bytes,
      );

  void recordCapturedOutputCleared(int executionCount) =>
      agentActionMetrics.recordCapturedOutputCleared(executionCount);

  void recordElevatedStatusFileTerminalRead() => agentActionMetrics.recordElevatedStatusFileTerminalRead();

  void recordElevatedStatusFileWaitTimeout() => agentActionMetrics.recordElevatedStatusFileWaitTimeout();

  void recordWorkerStarted(int activeCount) => sqlQueueMetrics.recordWorkerStarted(activeCount);

  void recordWorkerCompleted(int activeCount) => sqlQueueMetrics.recordWorkerCompleted(activeCount);

  void recordStreamingWorkerHoldTime(Duration holdTime) => sqlQueueMetrics.recordStreamingWorkerHoldTime(holdTime);

  void recordSqlQueueWorkersEqualPool({
    required int workers,
    required int poolSize,
  }) =>
      sqlQueueMetrics.recordSqlQueueWorkersEqualPool(workers: workers, poolSize: poolSize);

  void recordDiagnosticReason({
    required String category,
    required String reason,
  }) =>
      store.recordDiagnosticReason(category: category, reason: reason);

  void recordAutoUpdateManualCheckStarted() => autoUpdateMetrics.recordAutoUpdateManualCheckStarted();

  void recordAutoUpdateManualCheckSuccessAvailable() =>
      autoUpdateMetrics.recordAutoUpdateManualCheckSuccessAvailable();

  void recordAutoUpdateManualCheckSuccessNotAvailable() =>
      autoUpdateMetrics.recordAutoUpdateManualCheckSuccessNotAvailable();

  void recordAutoUpdateManualCheckUpdaterError() => autoUpdateMetrics.recordAutoUpdateManualCheckUpdaterError();

  void recordAutoUpdateManualCheckTriggerTimeout() => autoUpdateMetrics.recordAutoUpdateManualCheckTriggerTimeout();

  void recordAutoUpdateManualCheckCompletionTimeout() =>
      autoUpdateMetrics.recordAutoUpdateManualCheckCompletionTimeout();

  void recordAutoUpdateManualCheckTriggerFailure() => autoUpdateMetrics.recordAutoUpdateManualCheckTriggerFailure();

  void recordAutoUpdateManualCheckNotInitialized() => autoUpdateMetrics.recordAutoUpdateManualCheckNotInitialized();

  void recordAutoUpdateCircuitOpened() => autoUpdateMetrics.recordAutoUpdateCircuitOpened();

  void recordAutoUpdateCircuitOpenRejected() => autoUpdateMetrics.recordAutoUpdateCircuitOpenRejected();

  void recordAutoUpdateBackgroundCheckTriggerFailure() =>
      autoUpdateMetrics.recordAutoUpdateBackgroundCheckTriggerFailure();

  void recordAutoUpdateBackgroundCheckUpdaterError() =>
      autoUpdateMetrics.recordAutoUpdateBackgroundCheckUpdaterError();

  void recordAutoUpdateNotificationsPreferenceEnabled() =>
      autoUpdateMetrics.recordAutoUpdateNotificationsPreferenceEnabled();

  void recordAutoUpdateNotificationsPreferenceDisabled() =>
      autoUpdateMetrics.recordAutoUpdateNotificationsPreferenceDisabled();

  void recordAutoUpdateAutomaticSilentPreferenceEnabled() =>
      autoUpdateMetrics.recordAutoUpdateAutomaticSilentPreferenceEnabled();

  void recordAutoUpdateAutomaticSilentPreferenceDisabled() =>
      autoUpdateMetrics.recordAutoUpdateAutomaticSilentPreferenceDisabled();

  void recordAutoUpdateManualOnlyModeApplied() => autoUpdateMetrics.recordAutoUpdateManualOnlyModeApplied();

  void recordAutoUpdateProbeDuration(Duration duration) => autoUpdateMetrics.recordAutoUpdateProbeDuration(duration);

  void recordAutoUpdateDownloadDuration(Duration duration) =>
      autoUpdateMetrics.recordAutoUpdateDownloadDuration(duration);

  void recordAutoUpdateAwaitingUserConsent() => autoUpdateMetrics.recordAutoUpdateAwaitingUserConsent();

  void recordAutoUpdateUserInitiatedApplySuccess() => autoUpdateMetrics.recordAutoUpdateUserInitiatedApplySuccess();

  void recordAutoUpdateUserInitiatedApplyFailure() => autoUpdateMetrics.recordAutoUpdateUserInitiatedApplyFailure();

  void recordSuccess({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required int rowsAffected,
    required int columnCount,
  }) {
    _addMetric(
      QueryMetrics.success(
        queryId: queryId,
        query: query,
        executionDuration: executionDuration,
        rowsAffected: rowsAffected,
        columnCount: columnCount,
      ),
    );
  }

  void recordFailure({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required String errorMessage,
  }) {
    _addMetric(
      QueryMetrics.failure(
        queryId: queryId,
        query: query,
        executionDuration: executionDuration,
        errorMessage: errorMessage,
      ),
    );
  }

  MetricsSummary getSummary({int limit = 100}) {
    final List<QueryMetrics> recent;
    if (_metrics.length > limit) {
      recent = _metrics.skip(_metrics.length - limit).toList(growable: false);
    } else {
      recent = _metrics.toList(growable: false);
    }
    return MetricsSummary.fromList(recent);
  }

  List<QueryMetrics> getMetrics({bool? success}) {
    if (success == null) return List.unmodifiable(_metrics);
    return _metrics.where((m) => m.success == success).toList();
  }

  List<QueryMetrics> getSlowQueries({
    Duration threshold = const Duration(seconds: 1),
  }) {
    return _metrics.where((m) => m.executionDuration > threshold).toList()
      ..sort((a, b) => b.executionDuration.compareTo(a.executionDuration));
  }

  void _addMetric(QueryMetrics metric) {
    _metrics.addLast(metric);
    while (_metrics.length > _maxMetrics) {
      _metrics.removeFirst();
    }

    if (!metric.success) {
      developer.log(
        'QueryMetric: ${metric.executionDuration.inMilliseconds}ms, '
        'rows: ${metric.rowsAffected}, success: false',
        name: 'metrics',
        level: 1000,
      );
    }

    if (!_metricsController.isClosed) {
      _metricsController.add(metric);
    }
  }

  void _incrementEventCounter(String counter) => store.incrementEventCounter(counter);

  void _recordDurationSample(ListQueue<Duration> samples, Duration value) =>
      store.recordDurationSample(samples, value);

  void _recordTimestampSample(ListQueue<DateTime> samples, DateTime value) =>
      store.recordTimestampSample(samples, value);

  List<Map<String, dynamic>> exportToJson() => _metrics.map((m) => m.toMap()).toList();

  Map<String, Object> getSnapshot() {
    return MetricsCollectorSnapshotBuilder.build(
      queryMetrics: _metrics,
      store: store,
      p95QueueWaitTime: p95QueueWaitTime,
      maxRecentQueueWaitTime: maxRecentQueueWaitTime,
      sqlQueueRejectionCount: sqlQueueRejectionCount,
      sqlQueueTimeoutCount: sqlQueueTimeoutCount,
      sqlQueueTimeoutAfterWorkerStartedCount: sqlQueueTimeoutAfterWorkerStartedCount,
      sqlQueueSaturation70Count: sqlQueueSaturation70Count,
      sqlQueueSaturation90Count: sqlQueueSaturation90Count,
      sqlQueueWorkersEqualPoolCount: sqlQueueWorkersEqualPoolCount,
    );
  }

  List<int> _sortedQueueWaitTimesMs() {
    return store.queueWaitTimes.map((d) => d.inMilliseconds).toList()..sort();
  }

  void dispose() {
    _metricsController.close();
  }
}
