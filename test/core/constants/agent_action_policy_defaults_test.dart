import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';

void main() {
  group('AgentActionPolicyDefaults', () {
    test('should use conservative defaults when env is unset', () {
      expect(AgentActionPolicyDefaults.maxConcurrentActions, 1);
      expect(AgentActionPolicyDefaults.maxQueuedActions, 100);
      expect(AgentActionPolicyDefaults.defaultQueueTimeout, const Duration(minutes: 5));
      expect(AgentActionPolicyDefaults.defaultMaxRuntime, const Duration(minutes: 30));
      expect(AgentActionPolicyDefaults.maxRetryAttempts, 1);
      expect(AgentActionPolicyDefaults.maxContextBytes, 256 * 1024);
      expect(AgentActionPolicyDefaults.maxCapturedOutputBytes, 64 * 1024);
      expect(AgentActionPolicyDefaults.defaultPreflightValidityDays, 30);
      expect(AgentActionPolicyDefaults.preflightValidityDuration, const Duration(days: 30));
    });

    test('should expose queue limits for capabilities', () {
      final queue = AgentActionPolicyDefaults.defaultQueueLimitsCapability;
      expect(queue['maxConcurrent'], AgentActionPolicyDefaults.maxConcurrentActions);
      expect(queue['maxQueued'], AgentActionPolicyDefaults.maxQueuedActions);
      expect(queue['queueTimeoutMs'], AgentActionPolicyDefaults.defaultQueueTimeoutMs);
    });
  });
}
