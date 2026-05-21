import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

void main() {
  group('AgentActionExecutionMetricsCollector', () {
    test('should record terminal outcomes and execution duration in snapshot', () {
      final metrics = MetricsCollector()
        ..recordTerminalOutcome(AgentActionExecutionStatus.succeeded)
        ..recordTerminalOutcome(AgentActionExecutionStatus.failed)
        ..recordTerminalOutcome(AgentActionExecutionStatus.skipped)
        ..recordExecutionDuration(const Duration(milliseconds: 100))
        ..recordRemotePermissionDenied()
        ..recordRemoteAuditExecutionCorrelated();

      final snapshot = metrics.getSnapshot();
      expect(snapshot['agent_action_execution_terminal_succeeded'], 1);
      expect(snapshot['agent_action_execution_terminal_failed'], 1);
      expect(snapshot['agent_action_execution_terminal_skipped'], 1);
      expect(snapshot['agent_action_remote_permission_denied'], 1);
      expect(snapshot['agent_action_remote_audit_execution_correlated'], 1);
      expect(snapshot['agent_action_execution_sample_count'], 1);
      expect(snapshot['agent_action_execution_avg_time_ms'], 100.0);
    });

    test('should accumulate purge counters by removed row count', () {
      final metrics = MetricsCollector()
        ..recordExecutionHistoryPurge(3)
        ..recordRemoteAuditPurge(2)
        ..recordRpcIdempotencyCachePurge(5)
        ..recordElevatedBridgeArtifactsPurge(4)
        ..recordCapturedOutputCleared(2);

      final snapshot = metrics.getSnapshot();
      expect(snapshot['agent_action_execution_history_purge'], 3);
      expect(snapshot['agent_action_remote_audit_purge'], 2);
      expect(snapshot['agent_action_rpc_idempotency_cache_purge'], 5);
      expect(snapshot['agent_action_elevated_bridge_artifacts_purge'], 4);
      expect(snapshot['agent_action_captured_output_cleared'], 2);
    });

    test('should ignore non-positive purge amounts', () {
      final metrics = MetricsCollector()..recordExecutionHistoryPurge(0);

      expect(metrics.getSnapshot()['agent_action_execution_history_purge'], isNull);
    });

    test('should record cancel failure and captured output counters', () {
      final metrics = MetricsCollector()
        ..recordCancelKillFailed()
        ..recordCancelKillPermissionDenied()
        ..recordCancelProcessIdMismatch()
        ..recordCancelProcessIdentityUnavailable()
        ..recordCapturedOutputPersisted(
          stdoutCaptured: true,
          stderrCaptured: true,
          stdoutTruncated: true,
          stderrTruncated: false,
          stdoutUtf8Bytes: 12,
          stderrUtf8Bytes: 4,
        )
        ..recordElevatedStatusFileTerminalRead()
        ..recordElevatedStatusFileWaitTimeout();

      final snapshot = metrics.getSnapshot();
      expect(snapshot['agent_action_cancel_kill_failed'], 1);
      expect(snapshot['agent_action_cancel_kill_permission_denied'], 1);
      expect(snapshot['agent_action_cancel_process_id_mismatch'], 1);
      expect(snapshot['agent_action_cancel_process_identity_unavailable'], 1);
      expect(snapshot['agent_action_captured_output_stdout_truncated'], 1);
      expect(snapshot['agent_action_captured_output_stderr_truncated'], isNull);
      expect(snapshot['agent_action_captured_output_stdout_bytes'], 12);
      expect(snapshot['agent_action_captured_output_stderr_bytes'], 4);
      expect(snapshot['agent_action_elevated_status_file_terminal'], 1);
      expect(snapshot['agent_action_elevated_status_file_wait_timeout'], 1);
    });
  });
}
