import 'package:plug_agente/core/support/support_diagnostics_json_formatter.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';

class AgentActionRemoteAuditSupportExport {
  const AgentActionRemoteAuditSupportExport({
    SupportDiagnosticsJsonFormatter jsonFormatter = const SupportDiagnosticsJsonFormatter(),
  }) : _jsonFormatter = jsonFormatter;

  final SupportDiagnosticsJsonFormatter _jsonFormatter;

  String buildJson(List<AgentActionRemoteAuditRecord> records) {
    final payload = records
        .map(
          (record) => _jsonFormatter.flattenSections(
            <SupportDiagnosticsSection>[
              SupportDiagnosticsSection(
                title: 'Agent Action Remote Audit',
                fields: <SupportDiagnosticsField>[
                  SupportDiagnosticsField(key: 'id', value: record.id),
                  SupportDiagnosticsField(
                    key: 'occurred_at_utc',
                    value: record.occurredAtUtc.toIso8601String(),
                  ),
                  SupportDiagnosticsField(key: 'rpc_method', value: record.rpcMethod),
                  SupportDiagnosticsField(key: 'outcome', value: record.outcome),
                  SupportDiagnosticsField(
                    key: 'credential_present',
                    value: record.credentialPresent,
                  ),
                  SupportDiagnosticsField(key: 'action_id', value: record.actionId),
                  SupportDiagnosticsField(key: 'execution_id', value: record.executionId),
                  SupportDiagnosticsField(key: 'trace_id', value: record.traceId),
                  SupportDiagnosticsField(key: 'requested_by', value: record.requestedBy),
                  SupportDiagnosticsField(key: 'idempotency_key', value: record.idempotencyKey),
                  SupportDiagnosticsField(key: 'reason_code', value: record.reasonCode),
                  SupportDiagnosticsField(key: 'rpc_error_code', value: record.rpcErrorCode),
                  SupportDiagnosticsField(key: 'client_id', value: record.clientId),
                  SupportDiagnosticsField(key: 'token_jti', value: record.tokenJti),
                  SupportDiagnosticsField(
                    key: 'runtime_instance_id',
                    value: record.runtimeInstanceId,
                  ),
                  SupportDiagnosticsField(
                    key: 'runtime_session_id',
                    value: record.runtimeSessionId,
                  ),
                ],
              ),
            ],
            metadata: const <String, Object?>{
              'support_schema': 'plug_agente.support.v1',
              'support_category': 'agent_action_remote_audit',
            },
          ),
        )
        .toList(growable: false);

    return _jsonFormatter.buildPrettyJson(
      const <SupportDiagnosticsSection>[],
      metadata: <String, Object?>{
        'support_schema': 'plug_agente.support.v1',
        'support_category': 'agent_action_remote_audit_collection',
        'records': payload,
      },
    );
  }
}
