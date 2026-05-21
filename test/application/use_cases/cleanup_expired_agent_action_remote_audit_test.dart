import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_agent_action_remote_audit.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';

class _MockRemoteAuditStore extends Mock implements IAgentActionRemoteAuditStore {}

void main() {
  test('should sum deletions across batches until a zero batch', () async {
    final store = _MockRemoteAuditStore();
    var calls = 0;
    when(
      () => store.deleteWhereOccurredBefore(
        cutoffUtc: any(named: 'cutoffUtc'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async {
      calls++;
      return calls == 1 ? 2000 : 0;
    });

    final useCase = CleanupExpiredAgentActionRemoteAudit(
      store,
      retention: const Duration(days: 1),
      maxBatches: 10,
    );

    final result = await useCase();
    expect(result.isSuccess(), isTrue);
    expect(result.getOrThrow(), 2000);
    verify(
      () => store.deleteWhereOccurredBefore(cutoffUtc: any(named: 'cutoffUtc'), limit: 2000),
    ).called(2);
  });

  test('should return Failure when store throws', () async {
    final store = _MockRemoteAuditStore();
    when(
      () => store.deleteWhereOccurredBefore(
        cutoffUtc: any(named: 'cutoffUtc'),
        limit: any(named: 'limit'),
      ),
    ).thenThrow(StateError('db'));

    final useCase = CleanupExpiredAgentActionRemoteAudit(
      store,
      retention: const Duration(days: 1),
    );

    final result = await useCase();
    expect(result.isError(), isTrue);
  });
}
