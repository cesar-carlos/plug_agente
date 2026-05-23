import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/rpc_idempotency_coordinator.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

void main() {
  group('RpcIdempotencyCoordinator', () {
    late RpcIdempotencyCoordinator coordinator;

    setUp(() {
      coordinator = RpcIdempotencyCoordinator();
    });

    test('should run action only once for concurrent duplicate keys', () async {
      var executions = 0;
      final unblock = Completer<void>();

      Future<RpcResponse> executeOnce() {
        return coordinator.runExclusive(
          namespacedKey: 'sql.execute:shared-key',
          action: () async {
            executions++;
            await unblock.future;
            return RpcResponse.success(id: 'leader', result: const {'ok': true});
          },
        );
      }

      final first = executeOnce();
      final second = executeOnce();
      await pumpEventQueue();
      expect(executions, 1);

      unblock.complete();
      final responses = await Future.wait([first, second]);
      expect(executions, 1);
      expect(responses, everyElement(isA<RpcResponse>()));
      expect(responses.every((response) => response.isSuccess), isTrue);
    });

    test('should remap follower response id to caller request id', () async {
      final unblock = Completer<void>();

      final leader = coordinator.runExclusive(
        namespacedKey: 'agent.getHealth:health-key',
        action: () async {
          await unblock.future;
          return RpcResponse.success(id: 'leader-id', result: const {'status': 'ok'});
        },
      );
      final follower = coordinator.runExclusive(
        namespacedKey: 'agent.getHealth:health-key',
        action: () async {
          fail('follower should not execute action');
        },
      );

      unblock.complete();
      final leaderResponse = await leader;
      final followerResponse = await follower;

      expect(leaderResponse.id, 'leader-id');
      expect(
        coordinator.remapResponseId(followerResponse, 'follower-id').id,
        'follower-id',
      );
    });
  });
}
