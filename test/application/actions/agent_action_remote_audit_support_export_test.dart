import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_remote_audit_support_export.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';

void main() {
  group('AgentActionRemoteAuditSupportExport', () {
    const export = AgentActionRemoteAuditSupportExport();

    test('emits support metadata and remote audit records as structured json', () {
      final json = export.buildJson(
        <AgentActionRemoteAuditRecord>[
          AgentActionRemoteAuditRecord(
            id: 'audit-1',
            occurredAtUtc: DateTime.utc(2026, 5, 15, 12),
            rpcMethod: 'agent.action.run',
            outcome: 'success',
            credentialPresent: true,
            actionId: 'action-1',
            executionId: 'execution-1',
            traceId: 'trace-1',
            requestedBy: 'hub-user',
            clientId: 'client-1',
            runtimeInstanceId: 'inst-1',
            runtimeSessionId: 'sess-1',
          ),
        ],
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['support_schema'], 'plug_agente.support.v1');
      expect(decoded['support_category'], 'agent_action_remote_audit_collection');

      final records = decoded['records'] as List<dynamic>;
      expect(records, hasLength(1));

      final first = records.single as Map<String, dynamic>;
      expect(first['support_category'], 'agent_action_remote_audit');
      expect(first['rpc_method'], 'agent.action.run');
      expect(first['execution_id'], 'execution-1');
      expect(first['runtime_instance_id'], 'inst-1');
    });
  });
}
