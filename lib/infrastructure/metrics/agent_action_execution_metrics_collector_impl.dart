import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/repositories/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';

final class AgentActionExecutionMetricsCollectorImpl implements AgentActionExecutionMetricsCollector {
  AgentActionExecutionMetricsCollectorImpl(this._store);

  final MetricsEventStore _store;

  @override
  void recordTerminalOutcome(AgentActionExecutionStatus status) {
    final counter = switch (status) {
      AgentActionExecutionStatus.succeeded => MetricsCounterNames.agentActionExecutionTerminalSucceededCounter,
      AgentActionExecutionStatus.failed => MetricsCounterNames.agentActionExecutionTerminalFailedCounter,
      AgentActionExecutionStatus.skipped => MetricsCounterNames.agentActionExecutionTerminalSkippedCounter,
      AgentActionExecutionStatus.cancelled => MetricsCounterNames.agentActionExecutionTerminalCancelledCounter,
      AgentActionExecutionStatus.killed => MetricsCounterNames.agentActionExecutionTerminalKilledCounter,
      AgentActionExecutionStatus.timedOut => MetricsCounterNames.agentActionExecutionTerminalTimedOutCounter,
      AgentActionExecutionStatus.interrupted => MetricsCounterNames.agentActionExecutionTerminalInterruptedCounter,
      AgentActionExecutionStatus.unknown => MetricsCounterNames.agentActionExecutionTerminalUnknownCounter,
      AgentActionExecutionStatus.queued || AgentActionExecutionStatus.running => null,
    };
    if (counter != null) {
      _store.incrementEventCounter(counter);
    }
  }

  @override
  void recordExecutionDuration(Duration duration) {
    if (duration.isNegative) {
      return;
    }
    _store.recordDurationSample(_store.agentActionExecutionDurations, duration);
  }

  @override
  void recordRemotePermissionDenied() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionRemotePermissionDeniedCounter);
  }

  @override
  void recordLocalAuthorizationDenied() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionLocalAuthorizationDeniedCounter);
  }

  void recordRemoteRateLimited() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionRemoteRateLimitedCounter);
  }

  @override
  void recordExecutionHistoryPurge(int removedCount) {
    _store.incrementEventCounterBy(MetricsCounterNames.agentActionExecutionHistoryPurgeCounter, removedCount);
  }

  @override
  void recordRemoteAuditPurge(int removedCount) {
    _store.incrementEventCounterBy(MetricsCounterNames.agentActionRemoteAuditPurgeCounter, removedCount);
  }

  @override
  void recordRpcIdempotencyCachePurge(int removedCount) {
    _store.incrementEventCounterBy(MetricsCounterNames.agentActionRpcIdempotencyCachePurgeCounter, removedCount);
  }

  @override
  void recordElevatedBridgeArtifactsPurge(int removedCount) {
    _store.incrementEventCounterBy(MetricsCounterNames.agentActionElevatedBridgeArtifactsPurgeCounter, removedCount);
  }

  @override
  void recordRemoteAuditExecutionCorrelated() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionRemoteAuditExecutionCorrelatedCounter);
  }

  @override
  void recordCancelKillFailed() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionCancelKillFailedCounter);
  }

  @override
  void recordCancelKillPermissionDenied() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionCancelKillPermissionDeniedCounter);
  }

  @override
  void recordCancelProcessNotActive() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionCancelProcessNotActiveCounter);
  }

  @override
  void recordCancelProcessIdMismatch() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionCancelProcessIdMismatchCounter);
  }

  @override
  void recordCancelProcessIdentityMismatch() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionCancelProcessIdentityMismatchCounter);
  }

  @override
  void recordCancelProcessIdentityUnavailable() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionCancelProcessIdentityUnavailableCounter);
  }

  @override
  void recordCapturedOutputPersisted({
    required bool stdoutCaptured,
    required bool stderrCaptured,
    required bool stdoutTruncated,
    required bool stderrTruncated,
    int stdoutUtf8Bytes = 0,
    int stderrUtf8Bytes = 0,
  }) {
    if (stdoutCaptured && stdoutTruncated) {
      _store.incrementEventCounter(MetricsCounterNames.agentActionCapturedStdoutTruncatedCounter);
    }
    if (stderrCaptured && stderrTruncated) {
      _store.incrementEventCounter(MetricsCounterNames.agentActionCapturedStderrTruncatedCounter);
    }
    _store.incrementEventCounterBy(MetricsCounterNames.agentActionCapturedStdoutBytesCounter, stdoutUtf8Bytes);
    _store.incrementEventCounterBy(MetricsCounterNames.agentActionCapturedStderrBytesCounter, stderrUtf8Bytes);
  }

  @override
  void recordCapturedOutputCleared(int executionCount) {
    _store.incrementEventCounterBy(MetricsCounterNames.agentActionCapturedOutputClearedCounter, executionCount);
  }

  @override
  void recordElevatedStatusFileTerminalRead() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionElevatedStatusFileTerminalCounter);
  }

  @override
  void recordElevatedStatusFileWaitTimeout() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionElevatedStatusFileWaitTimeoutCounter);
  }
}
