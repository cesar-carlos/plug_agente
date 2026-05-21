import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

void main() {
  group('AgentActionRetentionSettings', () {
    test('should use environment defaults when store is empty', () {
      final settings = AgentActionRetentionSettings(InMemoryAppSettingsStore());

      expect(settings.executionRetentionDays, AgentActionRetentionSettings.defaultExecutionRetentionDays);
      expect(settings.remoteAuditRetentionDays, AgentActionRetentionSettings.defaultRemoteAuditRetentionDays);
      expect(settings.capturedOutputRetentionHours, AgentActionRetentionSettings.defaultCapturedOutputRetentionHours);
    });

    test('should prefer persisted values over defaults', () async {
      final store = InMemoryAppSettingsStore();
      final settings = AgentActionRetentionSettings(store);

      await settings.save(
        executionDays: 10,
        remoteAuditDays: 30,
        capturedOutputHours: 12,
      );

      expect(settings.executionRetentionDays, 10);
      expect(settings.remoteAuditRetentionDays, 30);
      expect(settings.capturedOutputRetentionHours, 12);
      expect(settings.hasPersistedOverrides, isTrue);
    });

    test('should clear persisted overrides and fall back to defaults', () async {
      final store = InMemoryAppSettingsStore();
      final settings = AgentActionRetentionSettings(store);

      await settings.save(
        executionDays: 10,
        remoteAuditDays: 30,
        capturedOutputHours: 12,
      );
      expect(settings.hasPersistedOverrides, isTrue);

      await settings.clearPersistedOverrides();

      expect(settings.hasPersistedOverrides, isFalse);
      expect(settings.executionRetentionDays, AgentActionRetentionSettings.defaultExecutionRetentionDays);
      expect(settings.remoteAuditRetentionDays, AgentActionRetentionSettings.defaultRemoteAuditRetentionDays);
      expect(settings.capturedOutputRetentionHours, AgentActionRetentionSettings.defaultCapturedOutputRetentionHours);
    });

    test('should clamp captured output hours to execution retention window', () async {
      final settings = AgentActionRetentionSettings(InMemoryAppSettingsStore());

      await settings.save(
        executionDays: 2,
        remoteAuditDays: 30,
        capturedOutputHours: 999,
      );

      expect(settings.capturedOutputRetentionHours, 48);
    });

    test('should cap agent action rpc idempotency ttl at 24h when execution retention exceeds one day', () async {
      final settings = AgentActionRetentionSettings(InMemoryAppSettingsStore());

      await settings.save(
        executionDays: 10,
        remoteAuditDays: 30,
        capturedOutputHours: 12,
      );

      expect(settings.agentActionRpcIdempotencyTtl, const Duration(hours: 24));
    });

    test('should align agent action rpc idempotency ttl with execution retention up to one day', () async {
      final settings = AgentActionRetentionSettings(InMemoryAppSettingsStore());

      await settings.save(
        executionDays: 1,
        remoteAuditDays: 30,
        capturedOutputHours: 12,
      );

      expect(settings.agentActionRpcIdempotencyTtl, const Duration(days: 1));
    });
  });
}
