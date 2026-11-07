import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/action_io_rpc_call_context.dart';
import 'package:plug_agente/domain/protocol/rpc_protocol_meta.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validation_support.dart';

void main() {
  for (final offset in [-86400, 86400]) {
    test('accepts clock offset $offset but charges transit and decode time', () {
      var ticks = 5000;
      var cancelled = false;
      final context = ActionIoRpcCallContext(
        connectionId: 'session',
        deadline: DateTime.now().add(Duration(seconds: offset)),
        receivedMonotonicMs: 4000,
        monotonicNow: () => ticks,
        isBatch: false,
        isCancelled: () => cancelled,
      );
      final result = context.withRequestBudget(
        const RpcProtocolMeta(
          actionIoClockId: 'session',
          actionIoMonotonicDeadlineMs: 10000,
          actionIoRemainingMs: 9000,
          actionIoDeadlineUnixMs: 0,
        ),
        clockNegotiated: true,
      );
      expect(result.isActive, isTrue);
      expect(result.remaining, const Duration(seconds: 5));
      ticks = 10000;
      expect(result.isActive, isFalse);
      expect(result.withMonotonicBudget(clockId: 'session', deadlineMs: 99999, remainingMs: 30000).isActive, isFalse);
      ticks = 5000;
      cancelled = true;
      expect(result.withCancellation(() => false).isActive, isFalse);
    });
  }
  test('rejects old sessions, missing negotiation and missing clock metadata', () {
    final context = ActionIoRpcCallContext(
      connectionId: 'new',
      deadline: DateTime.now().add(const Duration(days: 1)),
      receivedMonotonicMs: 1,
      monotonicNow: () => 2,
      isBatch: false,
      isCancelled: () => false,
    );
    for (final negotiated in [false, true]) {
      expect(
        context
            .withRequestBudget(
              const RpcProtocolMeta(
                actionIoClockId: 'old',
                actionIoMonotonicDeadlineMs: 30000,
                actionIoRemainingMs: 30000,
                actionIoDeadlineUnixMs: 9999999999999,
              ),
              clockNegotiated: negotiated,
            )
            .isActive,
        isFalse,
      );
    }
    expect(context.withRequestBudget(null, clockNegotiated: true).isActive, isFalse);
    expect(context.withRequestBudget(null, clockNegotiated: false), same(context));
  });
  test('validates complete bounded clock metadata', () {
    final valid = <String, dynamic>{
      'action_io_clock_id': 'session',
      'action_io_monotonic_deadline_ms': 100,
      'action_io_remaining_ms': 100,
      'action_io_deadline_unix_ms': 0,
    };
    expect(RpcRequestSchemaValidationSupport.validateMeta(valid).isSuccess(), isTrue);
    for (final key in valid.keys) {
      final invalid = {...valid}..remove(key);
      expect(RpcRequestSchemaValidationSupport.validateMeta(invalid).isError(), isTrue, reason: key);
    }
  });
}
