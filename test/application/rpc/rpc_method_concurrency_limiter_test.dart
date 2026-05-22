import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/rpc_method_concurrency_limiter.dart';

void main() {
  group('RpcMethodConcurrencyLimiter', () {
    test('limits concurrency per method and client token', () {
      final limiter = RpcMethodConcurrencyLimiter(
        methodLimits: const <String, int>{'sql.execute': 1},
      );

      final first = limiter.tryAcquire(
        method: 'sql.execute',
        agentId: 'agent-1',
        clientToken: 'token-a',
      );
      final second = limiter.tryAcquire(
        method: 'sql.execute',
        agentId: 'agent-1',
        clientToken: 'token-a',
      );

      expect(first.acquired, isTrue);
      expect(second.acquired, isFalse);

      first.lease!.release();
      final third = limiter.tryAcquire(
        method: 'sql.execute',
        agentId: 'agent-1',
        clientToken: 'token-a',
      );
      expect(third.acquired, isTrue);
      third.lease!.release();
    });

    test('does not let one client block another client', () {
      final limiter = RpcMethodConcurrencyLimiter(
        methodLimits: const <String, int>{'sql.execute': 1},
      );

      final first = limiter.tryAcquire(
        method: 'sql.execute',
        agentId: 'agent-1',
        clientToken: 'token-a',
      );
      final second = limiter.tryAcquire(
        method: 'sql.execute',
        agentId: 'agent-1',
        clientToken: 'token-b',
      );

      expect(first.acquired, isTrue);
      expect(second.acquired, isTrue);
      first.lease!.release();
      second.lease!.release();
    });

    test('falls back to agent scope when token is absent', () {
      final limiter = RpcMethodConcurrencyLimiter(
        methodLimits: const <String, int>{'agent.getHealth': 1},
      );

      final first = limiter.tryAcquire(
        method: 'agent.getHealth',
        agentId: 'agent-1',
        clientToken: null,
      );
      final second = limiter.tryAcquire(
        method: 'agent.getHealth',
        agentId: 'agent-1',
        clientToken: null,
      );

      expect(first.acquired, isTrue);
      expect(second.acquired, isFalse);
      first.lease!.release();
    });
  });
}
