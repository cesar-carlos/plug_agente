import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';

class _MockStore extends Mock implements IAgentActionRemoteAuditStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      AgentActionRemoteAuditRecord(
        id: 'fb',
        occurredAtUtc: DateTime.utc(2026),
        rpcMethod: 'agent.action.run',
        outcome: 'success',
        credentialPresent: false,
      ),
    );
  });

  test('should return rows from store', () async {
    final store = _MockStore();
    final row = AgentActionRemoteAuditRecord(
      id: 'a1',
      occurredAtUtc: DateTime.utc(2026, 5, 18, 12),
      rpcMethod: 'agent.action.run',
      outcome: 'success',
      credentialPresent: true,
      actionId: 'act-1',
    );
    when(
      () => store.listRecent(limit: any(named: 'limit')),
    ).thenAnswer((_) async => <AgentActionRemoteAuditRecord>[row]);

    final useCase = ListRecentAgentActionRemoteAudit(store);
    final result = await useCase(limit: 50);

    check(result.isSuccess()).isTrue();
    check(result.getOrThrow().single.id).equals('a1');
    verify(() => store.listRecent(limit: 50)).called(1);
  });

  test('should return Failure when store throws', () async {
    final store = _MockStore();
    when(() => store.listRecent(limit: any(named: 'limit'))).thenThrow(StateError('db'));

    final useCase = ListRecentAgentActionRemoteAudit(store);
    final result = await useCase();

    check(result.isError()).isTrue();
  });
}
