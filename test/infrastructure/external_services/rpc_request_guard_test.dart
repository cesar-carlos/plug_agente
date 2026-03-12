import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_request.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';

void main() {
  group('RpcRequestGuard', () {
    test('should allow distinct requests inside limit', () {
      final guard = RpcRequestGuard(
        maxRequestsPerWindow: 5,
      );

      final firstResult = guard.evaluate(_requestWithId('req-1'));
      final secondResult = guard.evaluate(_requestWithId('req-2'));

      check(firstResult).equals(RpcRequestGuardResult.allow);
      check(secondResult).equals(RpcRequestGuardResult.allow);
    });

    test('should detect replay when request id repeats in window', () {
      final now = DateTime.utc(2026, 3, 12, 10);
      final guard = RpcRequestGuard(
        nowProvider: () => now,
      );

      final firstResult = guard.evaluate(_requestWithId('same-id'));
      final replayResult = guard.evaluate(_requestWithId('same-id'));

      check(firstResult).equals(RpcRequestGuardResult.allow);
      check(replayResult).equals(RpcRequestGuardResult.replayDetected);
    });

    test('should allow same id again after replay window expires', () {
      var now = DateTime.utc(2026, 3, 12, 10);
      final guard = RpcRequestGuard(
        nowProvider: () => now,
        replayWindow: const Duration(seconds: 30),
      );

      final firstResult = guard.evaluate(_requestWithId('same-id'));
      now = now.add(const Duration(seconds: 31));
      final secondResult = guard.evaluate(_requestWithId('same-id'));

      check(firstResult).equals(RpcRequestGuardResult.allow);
      check(secondResult).equals(RpcRequestGuardResult.allow);
    });

    test('should apply rate limit before replay detection', () {
      final now = DateTime.utc(2026, 3, 12, 10);
      final guard = RpcRequestGuard(
        nowProvider: () => now,
        maxRequestsPerWindow: 2,
      );

      final firstResult = guard.evaluate(_requestWithId('r-1'));
      final secondResult = guard.evaluate(_requestWithId('r-2'));
      final thirdResult = guard.evaluate(_requestWithId('r-2'));

      check(firstResult).equals(RpcRequestGuardResult.allow);
      check(secondResult).equals(RpcRequestGuardResult.allow);
      check(thirdResult).equals(RpcRequestGuardResult.rateLimited);
    });

    test('should stop rate limiting after window expires', () {
      var now = DateTime.utc(2026, 3, 12, 10);
      final guard = RpcRequestGuard(
        nowProvider: () => now,
        maxRequestsPerWindow: 2,
        rateLimitWindow: const Duration(seconds: 10),
      );

      guard.evaluate(_requestWithId('r-1'));
      guard.evaluate(_requestWithId('r-2'));
      final limitedResult = guard.evaluate(_requestWithId('r-3'));

      now = now.add(const Duration(seconds: 11));
      final recoveredResult = guard.evaluate(_requestWithId('r-4'));

      check(limitedResult).equals(RpcRequestGuardResult.rateLimited);
      check(recoveredResult).equals(RpcRequestGuardResult.allow);
    });
  });
}

RpcRequest _requestWithId(String id) {
  return RpcRequest(
    jsonrpc: '2.0',
    method: 'sql.query',
    id: id,
    params: const <String, dynamic>{},
  );
}
