import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_agent_action_remote_audit.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockAgentActionRepository extends Mock implements IAgentActionRepository {}

class _MockRemoteAuditStore extends Mock implements IAgentActionRemoteAuditStore {}

void main() {
  test('should apply AgentActionRetentionSettings windows to cleanup use cases', () async {
    final settings = AgentActionRetentionSettings(InMemoryAppSettingsStore());
    await settings.save(
      executionDays: 7,
      remoteAuditDays: 45,
      capturedOutputHours: 6,
    );
    final now = DateTime.utc(2026, 5, 20, 12);

    final repository = _MockAgentActionRepository();
    DateTime? executionCutoff;
    DateTime? capturedOutputCutoff;
    when(
      () => repository.cleanupExecutions(olderThan: any(named: 'olderThan')),
    ).thenAnswer((invocation) async {
      executionCutoff = invocation.namedArguments[#olderThan] as DateTime;
      return const Success(0);
    });
    when(
      () => repository.clearCapturedOutputOlderThan(olderThan: any(named: 'olderThan')),
    ).thenAnswer((invocation) async {
      capturedOutputCutoff = invocation.namedArguments[#olderThan] as DateTime;
      return const Success(0);
    });

    final auditStore = _MockRemoteAuditStore();
    DateTime? auditCutoff;
    when(
      () => auditStore.deleteWhereOccurredBefore(
        cutoffUtc: any(named: 'cutoffUtc'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((invocation) async {
      auditCutoff = invocation.namedArguments[#cutoffUtc] as DateTime;
      return 0;
    });

    await CleanupAgentActionExecutions(
      repository,
      retention: settings.executionRetention,
    )(now: now);
    await CleanupAgentActionCapturedOutput(
      repository,
      retention: settings.capturedOutputRetention,
    )(now: now);
    await CleanupExpiredAgentActionRemoteAudit(
      auditStore,
      retention: settings.remoteAuditRetention,
    )(referenceTime: now);

    expect(executionCutoff, now.subtract(const Duration(days: 7)));
    expect(capturedOutputCutoff, now.subtract(const Duration(hours: 6)));
    expect(auditCutoff, now.subtract(const Duration(days: 45)));
  });
}
