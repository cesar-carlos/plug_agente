import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';

void main() {
  group('AgentActionRemoteRateLimiter', () {
    test('should allow unlimited calls when maxCallsPerMinute is 0', () {
      final limiter = AgentActionRemoteRateLimiter(maxCallsPerMinute: 0);

      expect(
        limiter
            .tryAcquire(
              agentId: 'agent-1',
              method: AgentActionRpcConstants.agentActionRunRpcMethodName,
              actionId: 'action-1',
              requesterKey: 'hub',
            )
            .allowed,
        isTrue,
      );
      expect(
        limiter
            .tryAcquire(
              agentId: 'agent-1',
              method: AgentActionRpcConstants.agentActionRunRpcMethodName,
              actionId: 'action-1',
              requesterKey: 'hub',
            )
            .allowed,
        isTrue,
      );
    });

    test('should enforce max calls per minute per action scope', () {
      final limiter = AgentActionRemoteRateLimiter(maxCallsPerMinute: 2);

      expect(
        limiter
            .tryAcquire(
              agentId: 'agent-1',
              method: AgentActionRpcConstants.agentActionRunRpcMethodName,
              actionId: 'action-1',
              requesterKey: 'hub',
            )
            .allowed,
        isTrue,
      );
      expect(
        limiter
            .tryAcquire(
              agentId: 'agent-1',
              method: AgentActionRpcConstants.agentActionRunRpcMethodName,
              actionId: 'action-1',
              requesterKey: 'hub',
            )
            .allowed,
        isTrue,
      );
      final third = limiter.tryAcquire(
        agentId: 'agent-1',
        method: AgentActionRpcConstants.agentActionRunRpcMethodName,
        actionId: 'action-1',
        requesterKey: 'hub',
      );

      expect(third.allowed, isFalse);
      expect(third.retryAfter, isNotNull);
    });

    test('should track action scopes independently', () {
      final limiter = AgentActionRemoteRateLimiter(maxCallsPerMinute: 1);

      expect(
        limiter
            .tryAcquire(
              agentId: 'agent-1',
              method: AgentActionRpcConstants.agentActionRunRpcMethodName,
              actionId: 'action-1',
              requesterKey: 'hub',
            )
            .allowed,
        isTrue,
      );
      expect(
        limiter
            .tryAcquire(
              agentId: 'agent-1',
              method: AgentActionRpcConstants.agentActionRunRpcMethodName,
              actionId: 'action-2',
              requesterKey: 'hub',
            )
            .allowed,
        isTrue,
      );
      expect(
        limiter
            .tryAcquire(
              agentId: 'agent-1',
              method: AgentActionRpcConstants.agentActionCancelRpcMethodName,
              actionId: 'action-1',
              requesterKey: 'hub',
            )
            .allowed,
        isTrue,
      );
    });

    test('should cap distinct scope keys to avoid unbounded map growth', () {
      final limiter = AgentActionRemoteRateLimiter(
        maxCallsPerMinute: 1000,
        maxScopeEntries: 12,
        random: Random(0),
      );

      for (var i = 0; i < 200; i++) {
        limiter.tryAcquire(
          agentId: 'agent-1',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          actionId: 'action-$i',
          requesterKey: 'hub',
        );
      }

      expect(limiter.trackedScopeCount, lessThanOrEqualTo(12));
    });
  });
}
