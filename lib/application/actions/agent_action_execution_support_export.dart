import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/core/support/support_diagnostics_json_formatter.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';
import 'package:plug_agente/domain/actions/actions.dart';

/// Builds a redacted JSON support payload for a single [AgentActionExecution].
class AgentActionExecutionSupportExport {
  const AgentActionExecutionSupportExport({
    AgentActionFailureDiagnosticsResolver diagnosticsResolver = const AgentActionFailureDiagnosticsResolver(),
    SupportDiagnosticsJsonFormatter jsonFormatter = const SupportDiagnosticsJsonFormatter(),
    AgentActionRedactor redactor = const AgentActionRedactor(),
  }) : _diagnosticsResolver = diagnosticsResolver,
       _jsonFormatter = jsonFormatter,
       _redactor = redactor;

  final AgentActionFailureDiagnosticsResolver _diagnosticsResolver;
  final SupportDiagnosticsJsonFormatter _jsonFormatter;
  final AgentActionRedactor _redactor;

  String buildJson(AgentActionExecution execution) {
    final diagnostics = _diagnosticsResolver.resolve(execution);
    final sections = <SupportDiagnosticsSection>[
      SupportDiagnosticsSection(
        title: 'Agent Action Execution',
        fields: <SupportDiagnosticsField>[
          SupportDiagnosticsField(key: 'execution_id', value: execution.id),
          SupportDiagnosticsField(key: 'action_id', value: execution.actionId),
          SupportDiagnosticsField(key: 'action_type', value: execution.actionType.name),
          SupportDiagnosticsField(key: 'status', value: execution.status.name),
          SupportDiagnosticsField(key: 'source', value: execution.source.name),
          SupportDiagnosticsField(key: 'requested_at_utc', value: execution.requestedAt.toUtc().toIso8601String()),
          SupportDiagnosticsField(key: 'exit_code', value: execution.exitCode),
          SupportDiagnosticsField(key: 'idempotency_key', value: execution.idempotencyKey),
          SupportDiagnosticsField(key: 'requested_by', value: execution.requestedBy),
          SupportDiagnosticsField(key: 'trace_id', value: execution.traceId),
          SupportDiagnosticsField(key: 'runtime_instance_id', value: execution.runtimeInstanceId),
          SupportDiagnosticsField(key: 'runtime_session_id', value: execution.runtimeSessionId),
          SupportDiagnosticsField(key: 'trigger_id', value: execution.triggerId),
          SupportDiagnosticsField(key: 'trigger_type', value: execution.triggerType?.name),
          SupportDiagnosticsField(key: 'scheduled_at_utc', value: execution.scheduledAt?.toUtc().toIso8601String()),
          SupportDiagnosticsField(key: 'triggered_at_utc', value: execution.triggeredAt?.toUtc().toIso8601String()),
          SupportDiagnosticsField(
            key: 'queue_started_at_utc',
            value: execution.queueStartedAt?.toUtc().toIso8601String(),
          ),
          SupportDiagnosticsField(
            key: 'process_started_at_utc',
            value: execution.processStartedAt?.toUtc().toIso8601String(),
          ),
          SupportDiagnosticsField(key: 'finished_at_utc', value: execution.finishedAt?.toUtc().toIso8601String()),
          SupportDiagnosticsField(key: 'timeout_at_utc', value: execution.timeoutAt?.toUtc().toIso8601String()),
          SupportDiagnosticsField(key: 'pid', value: execution.pid),
          SupportDiagnosticsField(key: 'process_executable', value: execution.processExecutable),
          SupportDiagnosticsField(key: 'process_argument_count', value: execution.processArgumentCount),
          SupportDiagnosticsField(key: 'process_command_preview', value: execution.processCommandPreview),
          SupportDiagnosticsField(key: 'definition_snapshot_hash', value: execution.definitionSnapshotHash),
          SupportDiagnosticsField(key: 'context_hash', value: execution.contextHash),
          SupportDiagnosticsField(key: 'redaction_applied', value: execution.redactionApplied),
          SupportDiagnosticsField(key: 'failure_code', value: diagnostics.failureCode ?? execution.failureCode),
          SupportDiagnosticsField(key: 'failure_phase', value: diagnostics.failurePhase ?? execution.failurePhase),
          if (diagnostics.correctiveAction != null)
            SupportDiagnosticsField(
              key: 'corrective_action',
              value: diagnostics.correctiveAction!.wireValue,
            ),
          // stdout/stderr sao re-redigidos aqui mesmo quando
          // `redactBeforePersisting=false` na captura: o export de suporte e
          // copiado para clipboard/clipboard de operador e nao deve vazar
          // segredos nem padroes sensiveis na sessao de suporte.
          SupportDiagnosticsField(key: 'stdout', value: _redactNullable(execution.stdoutText)),
          SupportDiagnosticsField(key: 'stdout_truncated', value: execution.stdoutTruncated),
          SupportDiagnosticsField(key: 'stderr', value: _redactNullable(execution.stderrText)),
          SupportDiagnosticsField(key: 'stderr_truncated', value: execution.stderrTruncated),
          const SupportDiagnosticsField(key: 'support_export_redaction_applied', value: true),
        ],
      ),
    ];

    return _jsonFormatter.buildPrettyJson(
      sections,
      metadata: const <String, Object?>{
        'support_schema': 'plug_agente.support.v1',
        'support_category': 'agent_action_execution',
      },
    );
  }

  String? _redactNullable(String? value) {
    if (value == null) {
      return null;
    }
    return _redactor.redactText(value);
  }
}
