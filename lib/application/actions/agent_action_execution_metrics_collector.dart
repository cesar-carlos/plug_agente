import 'package:plug_agente/domain/actions/action_enums.dart';

/// Metrics for local agent action executions and maintenance purges.
///
/// Counter keys are stable for metrics snapshot export and agent.getHealth.
///
/// **Cardinality policy:** implementations must use fixed counter names only.
/// Do not add per-`actionId`, path, command, or file-name labels. Operational
/// detail belongs in redacted execution history and remote audit rows.
abstract class AgentActionExecutionMetricsCollector {
  void recordTerminalOutcome(AgentActionExecutionStatus status);

  void recordExecutionDuration(Duration duration);

  void recordRemotePermissionDenied();

  /// Local preflight gates (`RunAgentActionLocally`, validateRun) denied by policy.
  void recordLocalAuthorizationDenied();

  void recordExecutionHistoryPurge(int removedCount);

  void recordRemoteAuditPurge(int removedCount);

  void recordRpcIdempotencyCachePurge(int removedCount);

  void recordElevatedBridgeArtifactsPurge(int removedCount);

  /// Remote audit row linked to an execution id and runtime identity at append time.
  void recordRemoteAuditExecutionCorrelated();

  void recordCancelKillFailed();

  void recordCancelKillPermissionDenied();

  void recordCancelProcessNotActive();

  void recordCancelProcessIdMismatch();

  void recordCancelProcessIdentityMismatch();

  void recordCancelProcessIdentityUnavailable();

  void recordCapturedOutputPersisted({
    required bool stdoutCaptured,
    required bool stderrCaptured,
    required bool stdoutTruncated,
    required bool stderrTruncated,
    int stdoutUtf8Bytes = 0,
    int stderrUtf8Bytes = 0,
  });

  void recordCapturedOutputCleared(int executionCount);

  void recordElevatedStatusFileTerminalRead();

  void recordElevatedStatusFileWaitTimeout();
}
