import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/action_io_rpc_call_context.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validation_support.dart';

void main() {
  final received = DateTime.utc(2026, 10, 29);
  ActionIoRpcCallContext context() => ActionIoRpcCallContext(
    connectionId: 'connection',
    receivedAt: received,
    deadline: received.add(const Duration(seconds: 30)),
    isBatch: false,
    isCancelled: () => false,
  );

  test('transport budget charges decoding time and cannot extend the local deadline', () {
    final result = context().withTransportBudget(
      remainingMs: 12000,
      deadlineUnixMs: received.add(const Duration(seconds: 20)).millisecondsSinceEpoch,
    );
    expect(result.deadline, received.add(const Duration(seconds: 12)));
    expect(result.connectionId, 'connection');
    expect(
      result
          .withTransportBudget(
            remainingMs: 30000,
            deadlineUnixMs: received.add(const Duration(days: 1)).millisecondsSinceEpoch,
          )
          .deadline,
      result.deadline,
    );
  });

  test('absolute deadline charges transit delay and expired requests stay expired', () {
    final deadline = received.subtract(const Duration(seconds: 1));
    expect(
      context()
          .withTransportBudget(
            remainingMs: 30000,
            deadlineUnixMs: deadline.millisecondsSinceEpoch,
          )
          .deadline,
      deadline,
    );
  });

  test('clock offsets cannot extend the relative budget and may expire a delayed request', () {
    // The hub has 20 seconds left at dispatch; four seconds pass in transit.
    for (final scenario in [
      (hubOffsetSeconds: 0, expectedSeconds: 16),
      (hubOffsetSeconds: 5, expectedSeconds: 20),
      (hubOffsetSeconds: -5, expectedSeconds: 11),
      (hubOffsetSeconds: -20, expectedSeconds: -4),
    ]) {
      final hubDispatch = received
          .subtract(const Duration(seconds: 4))
          .add(
            Duration(seconds: scenario.hubOffsetSeconds),
          );
      final bounded = context().withTransportBudget(
        remainingMs: 20000,
        deadlineUnixMs: hubDispatch.add(const Duration(seconds: 20)).millisecondsSinceEpoch,
      );
      expect(bounded.deadline, received.add(Duration(seconds: scenario.expectedSeconds)));
      expect(bounded.deadline.isAfter(received.add(const Duration(seconds: 20))), isFalse);
    }
  });

  test('transport budget requires both bounded integer fields', () {
    for (final meta in <Map<String, dynamic>>[
      {'action_io_remaining_ms': 1},
      {'action_io_deadline_unix_ms': 1},
      {'action_io_remaining_ms': 30001, 'action_io_deadline_unix_ms': 1},
      {'action_io_remaining_ms': -1, 'action_io_deadline_unix_ms': 1},
      {'action_io_remaining_ms': 1, 'action_io_deadline_unix_ms': null},
      {'action_io_remaining_ms': 1, 'action_io_deadline_unix_ms': 8640000000000001},
    ]) {
      expect(RpcRequestSchemaValidationSupport.validateMeta(meta).isError(), isTrue);
    }
    expect(
      RpcRequestSchemaValidationSupport.validateMeta({
        'action_io_remaining_ms': 0,
        'action_io_deadline_unix_ms': 0,
      }).isSuccess(),
      isTrue,
    );
  });

  test('read cancellation composes with disconnect and survives deadline shortening', () {
    var disconnected = false;
    var abandoned = false;
    var waitNotifications = 0;
    final original = ActionIoRpcCallContext(
      connectionId: 'connection',
      deadline: received.add(const Duration(seconds: 30)),
      receivedAt: received,
      isBatch: false,
      isCancelled: () => disconnected,
      onReadWait: () => waitNotifications++,
    );
    final read = original
        .withCancellation(() => abandoned)
        .withTransportBudget(
          remainingMs: 10000,
          deadlineUnixMs: received.add(const Duration(seconds: 20)).millisecondsSinceEpoch,
        );
    expect(read.isCancelled(), isFalse);
    abandoned = true;
    expect(read.isCancelled(), isTrue);
    expect(original.isCancelled(), isFalse);
    abandoned = false;
    disconnected = true;
    expect(read.isCancelled(), isTrue);
    expect(read.deadline, received.add(const Duration(seconds: 10)));
    expect(read.receivedAt, received);
    read.onReadWait!();
    expect(waitNotifications, 1);
  });
}
